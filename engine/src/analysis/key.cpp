#include "mmn/key.hpp"

#include "mmn/dsp.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>
#include <numeric>

namespace mmn {
namespace {

const char* const kNames[12] = {"C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"};

double pearson(const Chroma& a, const Chroma& b) {
    const double ma = std::accumulate(a.begin(), a.end(), 0.0) / 12, mb = std::accumulate(b.begin(), b.end(), 0.0) / 12;
    double sab = 0, saa = 0, sbb = 0;
    for (int i = 0; i < 12; ++i) {
        sab += (a[i] - ma) * (b[i] - mb);
        saa += (a[i] - ma) * (a[i] - ma);
        sbb += (b[i] - mb) * (b[i] - mb);
    }
    return saa > 0 && sbb > 0 ? sab / std::sqrt(saa * sbb) : 0.0;
}

Chroma rotate(const Chroma& p, int tonic) {
    Chroma r{};
    for (int i = 0; i < 12; ++i) r[(i + tonic) % 12] = p[i];
    return r;
}

}  // namespace

Chroma chromagram(std::span<const float> mono, int sr) {
    // 1) Solo picos espectrales: la batería reparte energía por todo el espectro y aplana el
    //    cromagrama (con todos los bins y amplitud log, MIREX 0,16 en GiantSteps: azar).
    // 2) Afinación: desviación global en centésimas (media circular de los picos) y corrección.
    // 3) Armónicos: un pico en f también es el 3.er armónico de f/3 (una quinta por debajo):
    //    se le devuelve parte de su peso a esa clase.
    // 4) Cada marco se normaliza a máx 1 para que los pasajes fuertes no decidan solos.
    Chroma c{};
    std::size_t n_fft = 1;
    while (n_fft * 3 < static_cast<std::size_t>(sr * 0.186 * 2)) n_fft <<= 1;  // ~186 ms
    const Spectrogram s = stft_mag(mono, sr, n_fft, n_fft / 2);
    const double bin_hz = static_cast<double>(sr) / static_cast<double>(n_fft);
    const auto k_lo = static_cast<std::size_t>(std::max(2.0, std::ceil(100 / bin_hz)));
    const auto k_hi = std::min(s.bins - 2, static_cast<std::size_t>(5000 / bin_hz));
    struct Peak { std::size_t frame; double midi, mag; };
    std::vector<Peak> peaks;
    for (std::size_t t = 0; t < s.frames; ++t) {
        const float* m = s.row(t);
        double mean = 0;
        for (std::size_t k = k_lo; k <= k_hi; ++k) mean += m[k];
        mean /= static_cast<double>(k_hi - k_lo + 1);
        if (mean <= 0) continue;
        for (std::size_t k = k_lo; k <= k_hi; ++k) {
            if (!(m[k] > m[k - 1] && m[k] >= m[k + 1]) || m[k] < 2 * mean) continue;
            const double a = std::log(m[k - 1] + 1e-12), b = std::log(m[k] + 1e-12), g = std::log(m[k + 1] + 1e-12);
            const double den = a - 2 * b + g;
            const double delta = den != 0 ? std::clamp(0.5 * (a - g) / den, -0.5, 0.5) : 0.0;
            const double f = (static_cast<double>(k) + delta) * bin_hz;
            peaks.push_back({t, 69 + 12 * std::log2(f / 440.0), static_cast<double>(m[k])});
        }
    }
    double cs = 0, sn = 0;  // media circular de la desviación respecto al semitono
    for (const auto& p : peaks) {
        const double a = 2 * std::numbers::pi * (p.midi - std::round(p.midi));
        cs += p.mag * std::cos(a), sn += p.mag * std::sin(a);
    }
    const double tuning = (cs != 0 || sn != 0) ? std::atan2(sn, cs) / (2 * std::numbers::pi) : 0.0;  // en semitonos
    Chroma frame{};
    std::size_t cur = static_cast<std::size_t>(-1);
    auto flush = [&] {
        const double mx = *std::max_element(frame.begin(), frame.end());
        if (mx > 0)
            for (int i = 0; i < 12; ++i) c[i] += frame[i] / mx;
        frame.fill(0.0);
    };
    auto add = [&](double midi, double w) {
        const double pc = std::fmod(midi + 1200.0, 12.0);
        const int lo = static_cast<int>(std::floor(pc));
        const double wl = 1.0 - (pc - lo);
        frame[lo % 12] += w * wl;
        frame[(lo + 1) % 12] += w * (1 - wl);
    };
    constexpr double kFifthBelow = 0.35;  // peso devuelto a f/3
    for (const auto& p : peaks) {
        if (p.frame != cur) flush(), cur = p.frame;
        const double midi = p.midi - tuning;
        add(midi, p.mag);
        add(midi - 12 * std::log2(3.0), kFifthBelow * p.mag);
    }
    flush();
    const double mx = *std::max_element(c.begin(), c.end());
    if (mx > 0)
        for (auto& v : c) v /= mx;
    return c;
}

KeyProfiles profiles_krumhansl() {
    return {{6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88},
            {6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17}};
}

KeyProfiles profiles_temperley() {
    return {{5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0},
            {5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0}};
}

KeyProfiles profiles_giantsteps() {
    // Mediana de los cromagramas rotados a C, por modo (método de Faraldo et al., 2016), sobre
    // las 604 pistas anotadas de GiantSteps Key. MIREX en validación cruzada de 10 partes:
    // 0,652 ± 0,047 (Krumhansl: 0,542; Temperley: 0,444). Rehacer: tools/evaluar_tonalidad.py
    return {{1.0000, 0.3696, 0.6435, 0.3600, 0.6998, 0.6584, 0.4145, 0.9190, 0.3997, 0.6396, 0.4396, 0.5351},
            {1.0000, 0.4495, 0.5853, 0.6858, 0.4760, 0.6727, 0.4334, 0.8712, 0.5633, 0.4599, 0.6522, 0.4536}};
}

KeyProfiles profiles_default() { return profiles_giantsteps(); }

Key estimate_key(const Chroma& c, const KeyProfiles& p) {
    Key best, second;
    best.score = second.score = -2;
    for (int mode = 0; mode < 2; ++mode)
        for (int t = 0; t < 12; ++t) {
            const double r = pearson(c, rotate(mode ? p.minor : p.major, t));
            Key k;
            k.tonic = t;
            k.minor = mode == 1;
            k.score = r;
            if (r > best.score) second = best, best = k;
            else if (r > second.score) second = k;
        }
    best.margin = best.score - second.score;
    return best;
}

std::string Key::name() const {
    if (tonic < 0) return "?";
    return std::string(kNames[tonic]) + (minor ? " minor" : " major");
}

std::string Key::camelot() const {
    if (tonic < 0) return "?";
    const int major_pc = minor ? (tonic + 3) % 12 : tonic;  // relativa mayor
    const int n = (7 * major_pc + 8) % 12;
    return std::to_string(n == 0 ? 12 : n) + (minor ? "A" : "B");
}

Key parse_key(const std::string& s) {
    Key k;
    k.tonic = -1;
    if (s.empty()) return k;
    static const std::pair<const char*, int> roots[] = {
        {"C#", 1}, {"Db", 1}, {"D#", 3}, {"Eb", 3}, {"F#", 6}, {"Gb", 6}, {"G#", 8}, {"Ab", 8}, {"A#", 10},
        {"Bb", 10}, {"Cb", 11}, {"C", 0}, {"D", 2}, {"E", 4}, {"F", 5}, {"G", 7}, {"A", 9}, {"B", 11}};
    for (const auto& [name, pc] : roots)
        if (s.rfind(name, 0) == 0) {
            k.tonic = pc;
            break;
        }
    k.minor = s.find("minor") != std::string::npos || s.find("min") != std::string::npos;
    return k;
}

double mirex_score(const Key& e, const Key& r) {
    if (e.tonic < 0 || r.tonic < 0) return 0;
    if (e.tonic == r.tonic && e.minor == r.minor) return 1.0;
    if (e.minor == r.minor && ((e.tonic - r.tonic + 12) % 12 == 7 || (r.tonic - e.tonic + 12) % 12 == 7)) return 0.5;
    if (!r.minor && e.minor && e.tonic == (r.tonic + 9) % 12) return 0.3;  // relativa menor
    if (r.minor && !e.minor && e.tonic == (r.tonic + 3) % 12) return 0.3;  // relativa mayor
    if (e.tonic == r.tonic && e.minor != r.minor) return 0.2;              // paralela
    return 0;
}

}  // namespace mmn
