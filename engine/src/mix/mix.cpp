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

Buffer render_session(const std::vector<Track>& tracks, SessionInfo* info) {
    Buffer out;
    if (tracks.empty()) return out;
    const int sr = tracks.front().audio.sample_rate;
    const int nch = tracks.front().audio.channels();
    const std::size_t n = tracks.size();
    std::vector<Buffer> audio;
    for (const auto& t : tracks) audio.push_back(to_channels(to_rate(t.audio, sr), nch));

    // Línea de tiempo. Para la pista i: entra en m[i-1] (salvo la primera, que empieza en 0),
    // y la transición i→i+1 empieza en m[i] y dura tov[i].
    std::vector<Ramp> ramp;
    std::vector<double> m(n, 0.0), tov(n, 0.0), start(n, 0.0);
    for (std::size_t i = 0; i + 1 < n; ++i)
        ramp.push_back({tracks[i].grid.bpm, tracks[i + 1].grid.bpm, static_cast<double>(tracks[i].windows.phrase)}),
            tov[i] = ramp.back().seconds_at(tracks[i].windows.phrase);
    auto entry_t = [&](std::size_t i) { return tracks[i].grid.beat_time(tracks[i].windows.entry_beat); };
    auto exit_t = [&](std::size_t i) { return tracks[i].grid.beat_time(tracks[i].windows.exit_beat); };
    auto after_t = [&](std::size_t i) {  // donde la pista i sigue sola tras su entrada
        return entry_t(i) + tracks[i - 1].windows.phrase * tracks[i].grid.period();
    };
    for (std::size_t i = 0; i < n; ++i) {
        if (i == 0) start[i] = 0, m[i] = exit_t(0);
        else start[i] = m[i - 1], m[i] = m[i - 1] + tov[i - 1] + std::max(0.0, exit_t(i) - after_t(i));
    }
    // Fin de la mezcla: la última pista suena sola desde que termina su entrada hasta su final.
    const double total = n == 1 ? audio[0].seconds()
                                : m[n - 2] + tov[n - 2] + std::max(0.0, audio[n - 1].seconds() - after_t(n - 1));

    out.sample_rate = sr;
    const auto nout = static_cast<std::size_t>(std::llround(total * sr));
    out.ch.assign(static_cast<std::size_t>(nch), std::vector<float>(nout, 0.0f));

    for (std::size_t i = 0; i < n; ++i) {
        const Track& t = tracks[i];
        const double p = t.grid.period();
        const double s0 = start[i];
        const double e0 = (i + 1 < n) ? m[i] + tov[i] : total;
        // mapa local: u = tiempo de mezcla - s0 → tiempo de la pista
        const TimeMap map = [&, i, p](double u) {
            const double tm = s0 + u;
            if (i > 0 && tm < start[i] + tov[i - 1]) return entry_t(i) + ramp[i - 1].beat_at(tm - start[i]) * p;
            if (i + 1 < n && tm >= m[i]) return exit_t(i) + ramp[i].beat_at(tm - m[i]) * p;
            const double anchor_mix = i == 0 ? 0.0 : start[i] + tov[i - 1];
            const double anchor_src = i == 0 ? 0.0 : after_t(i);
            return anchor_src + (tm - anchor_mix);
        };
        const Buffer st = stretch(audio[i], map, e0 - s0);
        const auto off = static_cast<std::size_t>(std::llround(s0 * sr));
        for (std::size_t c = 0; c < out.ch.size(); ++c)
            for (std::size_t j = 0; j < st.frames() && off + j < nout; ++j) {
                const double tm = s0 + double(j) / sr;
                double g = 1.0;
                if (i > 0 && tm < start[i] + tov[i - 1])
                    g *= std::sin(0.5 * std::numbers::pi * std::min(1.0, ramp[i - 1].beat_at(tm - start[i]) / ramp[i - 1].beats));
                if (i + 1 < n && tm >= m[i])
                    g *= std::cos(0.5 * std::numbers::pi * std::min(1.0, ramp[i].beat_at(tm - m[i]) / ramp[i].beats));
                out.ch[c][off + j] += static_cast<float>(g) * st.ch[c][j];
            }
    }
    limit(out);  // en los solapes los temas van en fase: sin esto, satura
    if (info) {
        info->starts = start;
        info->joins.clear();
        for (std::size_t i = 0; i + 1 < n; ++i) info->joins.push_back({m[i], tov[i], 0.0, tracks[i].grid.bpm, tracks[i + 1].grid.bpm});
        info->total_s = out.seconds();
        for (auto& j : info->joins) j.total_s = info->total_s;
    }
    return out;
}

Buffer render_transition(const Track& a, const Track& bt, TransitionInfo* info) {
    SessionInfo si;
    Buffer out = render_session({a, bt}, &si);
    if (info) *info = si.joins.front();
    return out;
}

}  // namespace mmn
