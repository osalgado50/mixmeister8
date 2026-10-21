// Sonoridad (ITU-R BS.1770-4 / EBU R128): ponderación K, bloques de 400 ms con paso de 100 ms,
// puertas absoluta (−70 LUFS) y relativa (−10 LU), sonoridad momentánea (400 ms) y a corto plazo
// (3 s), y pico real (true peak) con sobremuestreo ×4.
#include "mmn_c.h"

#include <algorithm>
#include <cmath>
#include <deque>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;

struct Biquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;
    double run(double x) {
        const double y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return y;
    }
};

/// Ponderación K para cualquier frecuencia de muestreo (prototipos analógicos de la norma).
void kweight(double fs, Biquad& shelf, Biquad& hp) {
    {
        const double f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196;
        const double K = std::tan(kPi * f0 / fs), Vh = std::pow(10.0, G / 20.0), Vb = std::pow(Vh, 0.4996667741545416);
        const double a0 = 1.0 + K / Q + K * K;
        shelf.b0 = (Vh + Vb * K / Q + K * K) / a0;
        shelf.b1 = 2.0 * (K * K - Vh) / a0;
        shelf.b2 = (Vh - Vb * K / Q + K * K) / a0;
        shelf.a1 = 2.0 * (K * K - 1.0) / a0;
        shelf.a2 = (1.0 - K / Q + K * K) / a0;
    }
    {
        const double f0 = 38.13547087602444, Q = 0.5003270373238773;
        const double K = std::tan(kPi * f0 / fs), a0 = 1.0 + K / Q + K * K;
        hp.b0 = 1.0, hp.b1 = -2.0, hp.b2 = 1.0;
        hp.a1 = 2.0 * (K * K - 1.0) / a0;
        hp.a2 = (1.0 - K / Q + K * K) / a0;
    }
}

/// Sobremuestreo ×4 para el pico real: FIR polifásico (sinc con ventana de Kaiser, 32 tomas por fase).
struct TruePeak {
    static constexpr int kTaps = 32, kPhases = 4;
    double h[kPhases][kTaps];
    double hist[kTaps] = {};
    int pos = 0;
    double peak = 0;
    TruePeak() {
        const int N = kTaps * kPhases;
        const double beta = 7.0;
        auto bessel = [](double x) { double s = 1, t = 1; for (int k = 1; k < 25; ++k) { t *= (x / (2 * k)) * (x / (2 * k)); s += t; } return s; };
        for (int p = 0; p < kPhases; ++p)
            for (int k = 0; k < kTaps; ++k) {
                const int n = k * kPhases + p;
                const double m = n - (N - 1) / 2.0;
                const double x = m / kPhases;
                const double sinc = std::fabs(x) < 1e-12 ? 1.0 : std::sin(kPi * x) / (kPi * x);
                const double r = 2.0 * n / (N - 1) - 1.0;
                h[p][k] = sinc * bessel(beta * std::sqrt(std::max(0.0, 1 - r * r))) / bessel(beta);
            }
    }
    void run(double x) {
        hist[pos] = x;
        peak = std::max(peak, std::fabs(x));
        for (int p = 0; p < kPhases; ++p) {
            double y = 0;
            for (int k = 0; k < kTaps; ++k) y += h[p][k] * hist[(pos - k + kTaps) % kTaps];
            peak = std::max(peak, std::fabs(y));
        }
        pos = (pos + 1) % kTaps;
    }
};

}  // namespace

struct mmn_loud {
    double fs;
    int channels;
    Biquad shelf[2], hp[2];
    TruePeak tp[2];
    std::size_t sub_len, sub_n = 0;
    double sub_acc = 0;
    std::deque<double> recent;       // energías de los últimos 30 subbloques de 100 ms
    std::vector<double> blocks;      // energía media de cada bloque de 400 ms (para la integrada)
};

extern "C" {

mmn_loud* mmn_loud_new(double sample_rate, int channels) {
    auto* m = new mmn_loud;
    m->fs = sample_rate > 0 ? sample_rate : 44100;
    m->channels = std::clamp(channels, 1, 2);
    for (int c = 0; c < 2; ++c) kweight(m->fs, m->shelf[c], m->hp[c]);
    m->sub_len = static_cast<std::size_t>(m->fs * 0.1);
    return m;
}

void mmn_loud_free(mmn_loud* m) { delete m; }

void mmn_loud_add(mmn_loud* m, const float* left, const float* right, int frames) {
    if (!m || !left) return;
    const float* in[2] = {left, right ? right : left};
    const int nc = right ? m->channels : 1;
    for (int i = 0; i < frames; ++i) {
        double e = 0;
        for (int c = 0; c < nc; ++c) {
            const double x = in[c][i];
            m->tp[c].run(x);
            const double y = m->hp[c].run(m->shelf[c].run(x));
            e += y * y;                                  // G = 1 para L y R
        }
        m->sub_acc += e;
        if (++m->sub_n == m->sub_len) {
            m->recent.push_back(m->sub_acc / static_cast<double>(m->sub_len));
            if (m->recent.size() > 30) m->recent.pop_front();
            m->sub_acc = 0, m->sub_n = 0;
            if (m->recent.size() >= 4) {
                double z = 0;
                for (std::size_t k = m->recent.size() - 4; k < m->recent.size(); ++k) z += m->recent[k];
                m->blocks.push_back(z / 4);
            }
        }
    }
}

static double lufs(double z) { return z > 0 ? -0.691 + 10.0 * std::log10(z) : -HUGE_VAL; }

double mmn_loud_integrated(mmn_loud* m) {
    if (!m || m->blocks.empty()) return -HUGE_VAL;
    const double abs_gate = std::pow(10.0, (-70.0 + 0.691) / 10.0);
    double s = 0; std::size_t n = 0;
    for (double z : m->blocks) if (z > abs_gate) s += z, ++n;
    if (n == 0) return -HUGE_VAL;
    const double rel_gate = (s / static_cast<double>(n)) * std::pow(10.0, -10.0 / 10.0);
    s = 0, n = 0;
    for (double z : m->blocks) if (z > abs_gate && z > rel_gate) s += z, ++n;
    return n ? lufs(s / static_cast<double>(n)) : -HUGE_VAL;
}

double mmn_loud_momentary(mmn_loud* m) {
    if (!m || m->recent.size() < 4) return -HUGE_VAL;
    double z = 0;
    for (std::size_t k = m->recent.size() - 4; k < m->recent.size(); ++k) z += m->recent[k];
    return lufs(z / 4);
}

double mmn_loud_shortterm(mmn_loud* m) {
    if (!m || m->recent.empty()) return -HUGE_VAL;
    double z = 0;
    for (double v : m->recent) z += v;
    return lufs(z / static_cast<double>(m->recent.size()));
}

double mmn_loud_truepeak_db(mmn_loud* m) {
    if (!m) return -HUGE_VAL;
    const double p = std::max(m->tp[0].peak, m->tp[1].peak);
    return p > 0 ? 20.0 * std::log10(p) : -HUGE_VAL;
}

}  // extern "C"
