#include "mmn/mix.hpp"

#include "mmn/stretch.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace mmn {

Track load_track(const std::string& path) {
    Track t;
    t.audio = read_audio(path);
    t.grid = analyze_rhythm(to_mono(t.audio), t.audio.sample_rate).grid;
    t.windows = mix_windows(t.grid);
    return t;
}

namespace {

/// Rampa de tempo lineal en tiempos: T(β) = Ta + (Tb - Ta)·β/L. Tiempo transcurrido hasta β y
/// su inversa, en forma cerrada (∫ 60/T dβ = 60·L/ΔT · ln(T/Ta)).
struct Ramp {
    double ta, tb, beats;
    [[nodiscard]] double seconds_at(double beta) const {
        const double d = tb - ta;
        if (std::abs(d) < 1e-9) return beta * 60.0 / ta;
        return 60.0 * beats / d * std::log((ta + d * beta / beats) / ta);
    }
    [[nodiscard]] double beat_at(double s) const {
        const double d = tb - ta;
        if (std::abs(d) < 1e-9) return s * ta / 60.0;
        return (ta * std::exp(s * d / (60.0 * beats)) - ta) * beats / d;
    }
};

Buffer to_rate(const Buffer& in, int rate) {
    if (in.sample_rate == rate) return in;
    Buffer out;
    out.sample_rate = rate;
    for (const auto& c : in.ch) out.ch.push_back(resample(c, in.sample_rate, rate));
    return out;
}

Buffer to_channels(Buffer b, int n) {
    if (b.channels() == n) return b;
    if (b.channels() == 1) {
        b.ch.resize(static_cast<std::size_t>(n), b.ch[0]);
        return b;
    }
    Buffer m;
    m.sample_rate = b.sample_rate;
    m.ch.assign(static_cast<std::size_t>(n), to_mono(b));
    return m;
}

/// Limitador con anticipación: ganancia = mín(1, techo/|x|) sobre una ventana de `look`
/// muestras por delante (ataque instantáneo y sin sobrepasar), recuperación exponencial de
/// ~100 ms. Solo actúa donde hace falta: el resto de la mezcla conserva su volumen.
void limit(Buffer& b, double ceiling = 0.98) {
    const std::size_t n = b.frames();
    if (n == 0) return;
    const std::size_t look = static_cast<std::size_t>(0.005 * b.sample_rate);
    std::vector<double> need(n, 1.0);
    for (std::size_t i = 0; i < n; ++i) {
        double pk = 0;
        for (const auto& c : b.ch) pk = std::max(pk, static_cast<double>(std::abs(c[i])));
        if (pk > ceiling) need[i] = ceiling / pk;
    }
    // mínimo en [i, i+look]: cola monótona
    std::vector<double> g(n);
    std::vector<std::size_t> dq;
    std::size_t head = 0;
    for (std::size_t j = 0; j < n + look; ++j) {
        if (j < n) {
            while (dq.size() > head && need[dq.back()] >= need[j]) dq.pop_back();
            dq.push_back(j);
        }
        if (j >= look) {
            const std::size_t i = j - look;
            while (dq[head] < i) ++head;
            g[i] = need[dq[head]];
        }
    }
    const double rel = std::exp(-1.0 / (0.100 * b.sample_rate));
    double cur = 1.0;
    for (std::size_t i = 0; i < n; ++i) {
        cur = g[i] < cur ? g[i] : g[i] + (cur - g[i]) * rel;
        for (auto& c : b.ch) c[i] = static_cast<float>(c[i] * cur);
    }
}

}  // namespace

Buffer render_transition(const Track& a, const Track& bt, TransitionInfo* info) {
    const int sr = a.audio.sample_rate;
    const Buffer b_audio = to_channels(to_rate(bt.audio, sr), a.audio.channels());
    const double pa = a.grid.period(), pb = bt.grid.period();
    const int L = a.windows.phrase;
    const Ramp ramp{a.grid.bpm, bt.grid.bpm, static_cast<double>(L)};
    const double t0 = a.grid.beat_time(a.windows.exit_beat);   // en A y en la salida: A suena tal cual
    const double tov = ramp.seconds_at(L);                        // duración del solape
    const double b_in = bt.grid.beat_time(bt.windows.entry_beat); // inicio de la entrada de B
    const double b_after = b_in + L * pb;                         // donde B sigue sola
    const double b_rest = std::max(0.0, b_audio.seconds() - b_after);
    const double total = t0 + tov + b_rest;

    // A: identidad hasta t0, luego sigue la rampa tiempo a tiempo.
    const TimeMap map_a = [&](double t) { return t < t0 ? t : t0 + ramp.beat_at(t - t0) * pa; };
    // B (en su tiempo local u = t - t0): la rampa durante el solape, luego a su tempo.
    const TimeMap map_b = [&](double u) { return u < tov ? b_in + ramp.beat_at(u) * pb : b_after + (u - tov); };
    const Buffer sa = stretch(a.audio, map_a, t0 + tov);
    const Buffer sb = stretch(b_audio, map_b, tov + b_rest);

    Buffer out;
    out.sample_rate = sr;
    const auto n = static_cast<std::size_t>(std::llround(total * sr));
    out.ch.assign(static_cast<std::size_t>(a.audio.channels()), std::vector<float>(n, 0.0f));
    const auto i0 = static_cast<std::size_t>(std::llround(t0 * sr));
    for (std::size_t c = 0; c < out.ch.size(); ++c) {
        for (std::size_t i = 0; i < sa.frames() && i < n; ++i) {
            double g = 1.0;
            if (i >= i0) g = std::cos(0.5 * std::numbers::pi * std::min(1.0, ramp.beat_at(double(i - i0) / sr) / L));
            out.ch[c][i] += static_cast<float>(g) * sa.ch[c][i];
        }
        for (std::size_t j = 0; j < sb.frames() && i0 + j < n; ++j) {
            const double u = double(j) / sr;
            const double g = u < tov ? std::sin(0.5 * std::numbers::pi * ramp.beat_at(u) / L) : 1.0;
            out.ch[c][i0 + j] += static_cast<float>(g) * sb.ch[c][j];
        }
    }
    limit(out);  // los dos temas van en fase en el solape: sin esto, satura
    if (info) *info = {t0, tov, total, a.grid.bpm, bt.grid.bpm};
    return out;
}

}  // namespace mmn
