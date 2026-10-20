#include "mmn/analysis.hpp"

#include "mmn/dsp.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <numbers>
#include <numeric>

namespace mmn {
namespace {

constexpr double kTwoPi = 2.0 * std::numbers::pi;
/// Retardo del pico de flujo de graves respecto al ataque, en fracción de ventana.
/// Calibrado igual que kOnsetLag (ver onset_envelope).
constexpr double kLowOnsetLag = 0.38;

void normalize_max(std::vector<float>& v) {
    const float m = v.empty() ? 0.0f : *std::max_element(v.begin(), v.end());
    if (m > 0)
        for (auto& x : v) x /= m;
}

/// Resta la media móvil (ventana impar `w`) y rectifica: deja solo lo que sobresale.
void detrend(std::vector<float>& v, std::size_t w) {
    if (v.empty()) return;
    std::vector<double> pre(v.size() + 1, 0.0);
    for (std::size_t i = 0; i < v.size(); ++i) pre[i + 1] = pre[i] + v[i];
    std::vector<float> out(v.size());
    const std::size_t h = w / 2;
    for (std::size_t i = 0; i < v.size(); ++i) {
        const std::size_t a = i >= h ? i - h : 0, b = std::min(v.size(), i + h + 1);
        const double mean = (pre[b] - pre[a]) / static_cast<double>(b - a);
        out[i] = std::max(0.0f, static_cast<float>(v[i] - mean));
    }
    v.swap(out);
}

double interp(std::span<const float> v, double x) {
    if (x < 0) return 0;
    const auto i = static_cast<std::size_t>(x);
    if (i + 1 >= v.size()) return 0;
    const double f = x - static_cast<double>(i);
    return v[i] + f * (v[i + 1] - v[i]);
}

/// Autocorrelación sesgada hasta `max_lag`, normalizada por r[0].
std::vector<double> autocorr(std::span<const float> v, std::size_t max_lag) {
    std::vector<double> r(max_lag + 1, 0.0);
    // Vía FFT: O(n log n).
    std::size_t n = 1;
    while (n < 2 * v.size()) n <<= 1;
    const Fft fft(n);
    std::vector<cfloat> x(n);
    const double mean = std::accumulate(v.begin(), v.end(), 0.0) / static_cast<double>(std::max<std::size_t>(1, v.size()));
    for (std::size_t i = 0; i < v.size(); ++i) x[i] = static_cast<float>(v[i] - mean);
    fft.forward(x);
    for (auto& c : x) c = std::norm(c);
    fft.inverse(x);
    const double r0 = x[0].real();
    if (r0 <= 0) return r;
    for (std::size_t k = 0; k <= max_lag && k < n; ++k) r[k] = x[k].real() / r0;
    return r;
}

/// Coherencia de fase de la envolvente a frecuencia `f` (Hz): Σ env·e^{-i2πft}.
std::complex<double> coherence(const OnsetEnvelope& e, double f) {
    std::complex<double> acc = 0;
    const std::complex<double> step = std::polar(1.0, -kTwoPi * f * e.hop_s);
    std::complex<double> w = std::polar(1.0, -kTwoPi * f * e.offset_s);
    for (float x : e.full) {
        acc += static_cast<double>(x) * w;
        w *= step;
    }
    return acc;
}

/// Puntuación de una rejilla de periodo P: fundamental + corcheas + semicorcheas.
double grid_score(const OnsetEnvelope& e, double period) {
    return std::abs(coherence(e, 1.0 / period)) + 0.5 * std::abs(coherence(e, 2.0 / period)) +
           0.25 * std::abs(coherence(e, 4.0 / period));
}

}  // namespace

std::array<double, 8> phase_features(const OnsetEnvelope& e, double t0, double P) {
    std::array<double, 8> out{};
    const std::size_t nb = e.n_bands;
    if (!nb || P <= 0) return out;
    const std::size_t frames = e.bands.size() / nb;
    // Grupo de cada banda por su frecuencia central (bandas log de 30 Hz a 8 kHz).
    std::vector<int> group(nb);
    std::array<int, 4> members{};
    for (std::size_t b = 0; b < nb; ++b) {
        const double lo = 30.0 * std::pow(8000.0 / 30.0, double(b) / double(nb));
        const double hi = 30.0 * std::pow(8000.0 / 30.0, double(b + 1) / double(nb));
        const double c = std::sqrt(lo * hi);
        group[b] = c < 90 ? 0 : c < 250 ? 1 : c < 2000 ? 2 : 3;
        ++members[group[b]];
    }
    auto B = [&](long f, std::size_t b) { return static_cast<double>(e.bands[static_cast<std::size_t>(f) * nb + b]); };
    long n = 0;
    std::array<double, 8> acc{};
    for (double t = std::fmod(t0, P); t + 0.2 < e.duration(); t += P) {
        const auto i = static_cast<long>(std::floor((t - e.frame_offset_s) / e.hop_s));
        const long f30 = std::lround((t + 0.030) / e.hop_s), f150 = std::lround((t + 0.150) / e.hop_s);
        if (i < 2 || f150 >= static_cast<long>(frames) || i + 2 >= static_cast<long>(frames)) continue;
        for (std::size_t b = 0; b < nb; ++b) {
            double flux = 0;  // máximo del flujo positivo en ±1 frame
            for (long f = i - 1; f <= i + 2; ++f) flux = std::max(flux, B(f, b) - B(f - 1, b));
            acc[group[b]] += flux / members[group[b]];
            acc[4 + group[b]] += (B(f30, b) - B(f150, b)) / members[group[b]];
        }
        ++n;
    }
    if (n)
        for (int k = 0; k < 8; ++k) out[k] = acc[k] / static_cast<double>(n);
    return out;
}

double phase_score(const OnsetEnvelope& e, double t0, double P) {
    // Pesos de una regresión logística sobre 181 pistas reales emparejadas con su .mxm de
    // MixMeister (tiempo frente a contratiempo). Validación cruzada en 10 partes: 88,9 % ± 5,6 %.
    // Lectura: subgraves y medios a favor (bombo, caja), agudos en contra (charles a
    // contratiempo), caída rápida en graves a favor (cuerpo del bombo frente a bajo sostenido).
    // Rehacer con: mmn phasediag + engine/tools/ajustar_fase.py
    static constexpr std::array<double, 8> w{5.7279, 0.2792, 3.5734, -3.7351, -1.1405, 1.4199, -1.0003, 1.3352};
    const auto f = phase_features(e, t0, P);
    double s = 0;
    for (int k = 0; k < 8; ++k) s += w[k] * f[k];
    return s;
}

OnsetEnvelope onset_envelope(std::span<const float> mono, int sr) {
    // Ventana de ~46 ms: la potencia de dos más cercana (no la superior: a 48 kHz serían 85 ms).
    std::size_t n_fft = 1;
    while (n_fft * 3 < static_cast<std::size_t>(sr * 0.046 * 2)) n_fft <<= 1;
    const auto hop = static_cast<std::size_t>(std::lround(sr * 0.0058));
    const Spectrogram s = stft_mag(mono, sr, n_fft, hop);
    const double bin_hz = static_cast<double>(sr) / static_cast<double>(n_fft);
    const auto k_lo = static_cast<std::size_t>(std::ceil(30 / bin_hz));
    const auto k_bass = static_cast<std::size_t>(150 / bin_hz);
    const auto k_hi = std::min(s.bins - 1, static_cast<std::size_t>(16000 / bin_hz));

    OnsetEnvelope e;
    e.hop_s = static_cast<double>(hop) / sr;
    // El flujo en t mide el cambio entre los frames t-1 y t, centrados en (t-1)·hop y t·hop.
    // Con ventana de Hann el flujo crece antes de que el ataque llegue al centro: el pico
    // se adelanta una fracción fija de la ventana. kOnsetLag está calibrado con ataques
    // sintéticos (tests/test_rhythm.cpp, "Tempo y fase exactos").
    constexpr double kOnsetLag = 0.205;
    e.offset_s = -0.5 * e.hop_s + kOnsetLag * static_cast<double>(n_fft) / sr;
    e.low_offset_s = -0.5 * e.hop_s + kLowOnsetLag * static_cast<double>(n_fft) / sr;
    e.frame_offset_s = 0.0;
    // Bandas logarítmicas para el análisis armónico/tímbrico.
    e.n_bands = 48;
    std::vector<std::size_t> edge(e.n_bands + 1);
    for (std::size_t b = 0; b <= e.n_bands; ++b)
        edge[b] = std::min(s.bins - 1, static_cast<std::size_t>(30.0 * std::pow(8000.0 / 30.0, double(b) / double(e.n_bands)) / bin_hz));
    e.bands.assign(s.frames * e.n_bands, 0.0f);
    e.full.assign(s.frames, 0.0f);
    e.low.assign(s.frames, 0.0f);
    std::vector<float> prev(s.bins, 0.0f), cur(s.bins);
    for (std::size_t t = 0; t < s.frames; ++t) {
        const float* m = s.row(t);
        for (std::size_t k = 0; k < s.bins; ++k) cur[k] = std::log1p(100.0f * m[k]);
        for (std::size_t b = 0; b < e.n_bands; ++b) {
            const std::size_t a0 = edge[b], a1 = std::max(edge[b] + 1, edge[b + 1]);
            float acc = 0;
            for (std::size_t k = a0; k < a1; ++k) acc += m[k];
            e.bands[t * e.n_bands + b] = std::log1p(100.0f * acc / static_cast<float>(a1 - a0));
        }
        if (t > 0) {
            float full = 0, low = 0;
            for (std::size_t k = k_lo; k <= k_hi; ++k) {
                const float d = cur[k] - prev[k];
                if (d > 0) {
                    full += d;
                    if (k <= k_bass) low += d;
                }
            }
            e.full[t] = full;
            e.low[t] = low;
        }
        prev.swap(cur);
    }
    const auto w = static_cast<std::size_t>(std::lround(0.4 / e.hop_s)) | 1u;
    detrend(e.full, w);
    detrend(e.low, w);
    normalize_max(e.full);
    normalize_max(e.low);
    return e;
}

std::vector<TempoCandidate> tempo_candidates(const OnsetEnvelope& e, const TempoOptions& o) {
    std::vector<TempoCandidate> out;
    if (e.full.size() < 64) return out;
    const double max_lag_s = 4 * 60.0 / o.min_bpm;
    const auto max_lag = std::min(e.full.size() - 1, static_cast<std::size_t>(max_lag_s / e.hop_s) + 2);
    const auto r = autocorr(e.full, max_lag);
    auto ac = [&](double lag) {
        const auto i = static_cast<std::size_t>(lag);
        if (i + 1 >= r.size()) return 0.0;
        const double f = lag - static_cast<double>(i);
        return std::max(0.0, r[i] + f * (r[i + 1] - r[i]));
    };
    // Peine: un tempo T explica picos en sus múltiplos de periodo (1, 2, 3, 4 tiempos).
    std::vector<TempoCandidate> curve;
    for (double bpm = o.min_bpm; bpm <= o.max_bpm + 1e-9; bpm += 0.05) {
        const double lag = 60.0 / bpm / e.hop_s;
        // Solo múltiplos en potencias de dos (estructura de 4/4): con el 3 el peine premia
        // las tresillas y 174 BPM se lee como 116.
        const double s = ac(lag) + 0.5 * ac(2 * lag) + 0.25 * ac(4 * lag);
        const double oct = std::log2(bpm / o.prior_center_bpm) / o.prior_sigma_oct;
        curve.push_back({bpm, s, s * std::exp(-0.5 * oct * oct)});
    }
    // Máximos locales de la curva ponderada.
    for (std::size_t i = 1; i + 1 < curve.size(); ++i)
        if (curve[i].weighted >= curve[i - 1].weighted && curve[i].weighted > curve[i + 1].weighted) out.push_back(curve[i]);
    std::sort(out.begin(), out.end(), [](auto& a, auto& b) { return a.weighted > b.weighted; });
    if (out.size() > 8) out.resize(8);
    return out;
}

namespace {

/// Periodo y fase finos alrededor de bpm0 (sin confianza ni compás).
BeatGrid fit_grid(const OnsetEnvelope& e, double bpm0) {
    BeatGrid g;
    if (e.full.empty() || bpm0 <= 0) return g;
    auto score_bpm = [&](double bpm) { return grid_score(e, 60.0 / bpm); };
    // 1) Barrido en ±1,5 %. El pico del armónico 4 mide ~15/duración BPM de ancho: el paso
    //    se elige para caer al menos tres veces dentro.
    const double step = std::clamp(5.0 / std::max(1.0, e.duration()), 0.005, 0.04);
    double best = bpm0, best_s = -1;
    for (double b = bpm0 * 0.985; b <= bpm0 * 1.015; b += step) {
        const double s = score_bpm(b);
        if (s > best_s) best_s = s, best = b;
    }
    // 2) Sección áurea en ±paso hasta 1e-5 BPM.
    double lo = best - step, hi = best + step;
    const double phi = (std::sqrt(5.0) - 1) / 2;
    double x1 = hi - phi * (hi - lo), x2 = lo + phi * (hi - lo);
    double f1 = score_bpm(x1), f2 = score_bpm(x2);
    while (hi - lo > 1e-5) {
        if (f1 > f2) hi = x2, x2 = x1, f2 = f1, x1 = hi - phi * (hi - lo), f1 = score_bpm(x1);
        else lo = x1, x1 = x2, f1 = f2, x2 = lo + phi * (hi - lo), f2 = score_bpm(x2);
    }
    g.bpm = 0.5 * (lo + hi);
    const double P = g.period();

    // 3) Fase: la del fundamental, afinada maximizando la suma de ataques bajo la rejilla.
    const double ph0 = std::fmod(-std::arg(coherence(e, 1.0 / P)) / kTwoPi * P + 10 * P, P);
    // Un bombo es graves Y ataque de banda ancha a la vez: el producto distingue el bombo del
    // bajo a contratiempo (solo graves) y del charles abierto (solo agudos).
    auto phase_score = [&](double b0) {
        double s = 0;
        for (double t = b0; t <= e.duration(); t += P) {
            const double lo = interp(e.low, (t - e.low_offset_s) / e.hop_s);
            const double fu = interp(e.full, (t - e.offset_s) / e.hop_s);
            s += std::sqrt(lo * fu);
        }
        return s;
    };
    // El fundamental de la banda completa puede engancharse al contratiempo: se busca en
    // el periodo entero.
    double b0 = ph0, bs = -1;
    for (double d = -0.5 * P; d < 0.5 * P; d += e.hop_s / 4) {
        const double c = std::fmod(ph0 + d + P, P);
        const double s = phase_score(c);
        if (s > bs) bs = s, b0 = c;
    }
    // 4) Tiempo o contratiempo: decide la regla aprendida comparando las dos rejillas.
    const double other = std::fmod(b0 + 0.5 * P, P);
    if (mmn::phase_score(e, other, P) > mmn::phase_score(e, b0, P)) b0 = other;
    g.first_beat_s = b0;
    return g;
}

/// Fuerza media del ataque (graves + banda completa) justo bajo cada tiempo de la rejilla.
double pulse_strength(const OnsetEnvelope& e, const BeatGrid& g) {
    double s = 0;
    long n = 0;
    for (double t = g.first_beat_s; t <= e.duration(); t += g.period(), ++n) {
        s += interp(e.low, (t - e.low_offset_s) / e.hop_s) + 0.5 * interp(e.full, (t - e.offset_s) / e.hop_s);
    }
    return n ? s / static_cast<double>(n) : 0.0;
}

}  // namespace

BeatGrid refine_grid(const OnsetEnvelope& e, double bpm0) {
    BeatGrid g = fit_grid(e, bpm0);
    if (g.bpm <= 0) return g;
    auto score_bpm = [&](double bpm) { return grid_score(e, 60.0 / bpm); };
    const double P = g.period(), b0 = g.first_beat_s;

    // 4) Confianza: pico frente a la mediana de la rejilla en todo el rango de tempo.
    std::vector<double> bg;
    for (double b = 60; b <= 200; b += 0.53) bg.push_back(score_bpm(b));
    std::nth_element(bg.begin(), bg.begin() + bg.size() / 2, bg.end());
    const double med = bg[bg.size() / 2];
    g.confidence = med > 0 ? std::max(0.0, (score_bpm(g.bpm) / med - 1.0) / 4.0) : 0.0;

    // 5) Compás, con la convención de MixMeister y de los DJ: el compás 1 es el primer
    //    tiempo con sonido de verdad. (En las 11 demos del original, todos sus puntos de
    //    mezcla caen a múltiplos de 4 tiempos contados desde ahí.) Un tiempo "suena" si su
    //    ataque de bombo supera la mitad de la mediana de la pista.
    std::vector<double> strength;
    for (double t = b0; t <= e.duration(); t += P) {
        const double lo = interp(e.low, (t - e.low_offset_s) / e.hop_s);
        const double fu = interp(e.full, (t - e.offset_s) / e.hop_s);
        strength.push_back(std::sqrt(lo * fu));
    }
    if (!strength.empty()) {
        auto sorted = strength;
        std::nth_element(sorted.begin(), sorted.begin() + sorted.size() / 2, sorted.end());
        const double med = sorted[sorted.size() / 2];
        std::size_t k = 0;
        while (k < strength.size() && strength[k] < 0.5 * med) ++k;
        if (k == strength.size()) k = 0;
        g.downbeat = static_cast<int>(k % 4);
        g.first_sounding_beat = static_cast<long>(k);
    }
    return g;
}

RhythmAnalysis analyze_rhythm(std::span<const float> mono, int sr, const TempoOptions& opt) {
    RhythmAnalysis a;
    a.env = onset_envelope(mono, sr);
    a.candidates = tempo_candidates(a.env, opt);
    if (a.candidates.empty()) return a;
    // Nivel métrico. La autocorrelación premia los tempos lentos (en música en bucle todo se
    // repite cada compás), así que la decisión final la toma el pulso: la fuerza media del
    // ataque bajo cada tiempo de la rejilla, por el prior de nivel. Se prueban los tres
    // mejores candidatos y sus dobles y mitades.
    std::vector<double> levels;  // niveles a probar
    auto add = [&](double b) {
        if (b < opt.min_bpm || b > opt.max_bpm) return;
        for (double l : levels)
            if (std::abs(l / b - 1) < 0.015) return;
        levels.push_back(b);
    };
    // Solo la familia de octava del mejor candidato: el pulso decide el nivel, no el tempo.
    // (Con semicorcheas densas cualquier rejilla encuentra ataques; dejarle elegir entre
    // tempos sin relación de octava convertía 132 en 105.)
    const double top = a.candidates.front().bpm;
    // Con 3:2 y 2:3: las corcheas de un 174 hacen que la autocorrelación prefiera 116.
    add(top), add(2 * top), add(top / 2), add(top * 1.5), add(top / 1.5);
    double best_score = -1, best_bpm = a.candidates.front().bpm;
    for (double b : levels) {
        const BeatGrid g = fit_grid(a.env, b);
        const double oct = std::log2(g.bpm / opt.prior_center_bpm) / opt.prior_sigma_oct;
        const double sc = pulse_strength(a.env, g) * std::exp(-0.5 * oct * oct);
        if (sc > best_score) best_score = sc, best_bpm = g.bpm;
    }
    a.grid = refine_grid(a.env, best_bpm);
    return a;
}

}  // namespace mmn
