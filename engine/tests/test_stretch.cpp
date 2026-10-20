// Cambio de tempo: reconstrucción, tono, duración, tempo resultante y anclaje sin deriva.
#include "doctest.h"
#include "mmn/analysis.hpp"
#include "mmn/dsp.hpp"
#include "mmn/stretch.hpp"

#include <cmath>
#include <numbers>
#include <random>

using namespace mmn;

namespace {

Buffer tone(double f, double seconds, int sr) {
    Buffer b;
    b.sample_rate = sr;
    b.ch.assign(1, std::vector<float>(static_cast<std::size_t>(seconds * sr)));
    for (std::size_t i = 0; i < b.ch[0].size(); ++i) b.ch[0][i] = 0.5f * static_cast<float>(std::sin(2 * std::numbers::pi * f * i / sr));
    return b;
}

/// Frecuencia dominante por FFT con interpolación parabólica.
double peak_hz(const std::vector<float>& x, int sr) {
    const std::size_t n = 1 << 16;
    std::vector<float> seg(n, 0.0f);
    const std::size_t start = x.size() > n ? (x.size() - n) / 2 : 0;
    const auto w = hann(n);
    for (std::size_t i = 0; i < n && start + i < x.size(); ++i) seg[i] = x[start + i] * w[i];
    std::vector<cfloat> s(n / 2 + 1);
    Fft(n).real_forward(seg, s);
    std::size_t k = 1;
    for (std::size_t i = 2; i + 1 < s.size(); ++i)
        if (std::abs(s[i]) > std::abs(s[k])) k = i;
    const double a = std::log(std::abs(s[k - 1])), b = std::log(std::abs(s[k])), c = std::log(std::abs(s[k + 1]));
    return (static_cast<double>(k) + 0.5 * (a - c) / (a - 2 * b + c)) * sr / static_cast<double>(n);
}

Buffer clicks(double bpm, double seconds, int sr) {
    Buffer b;
    b.sample_rate = sr;
    b.ch.assign(1, std::vector<float>(static_cast<std::size_t>(seconds * sr), 0.0f));
    std::mt19937 rng(3);
    std::uniform_real_distribution<float> u(-1, 1);
    for (double t = 0.1; t < seconds; t += 60 / bpm) {
        const auto s0 = static_cast<std::size_t>(t * sr);
        for (std::size_t i = 0; i < static_cast<std::size_t>(0.05 * sr) && s0 + i < b.ch[0].size(); ++i) {
            const double tt = static_cast<double>(i) / sr;
            b.ch[0][s0 + i] += static_cast<float>(0.8 * std::exp(-tt / 0.03) * std::sin(2 * std::numbers::pi * 70 * tt)) +
                               0.2f * u(rng) * static_cast<float>(std::exp(-tt / 0.005));
        }
    }
    return b;
}

}  // namespace

TEST_CASE("A velocidad 1 la salida es la entrada") {
    const int sr = 44100;
    const Buffer in = tone(440, 3, sr);
    const Buffer out = stretch_constant(in, 1.0);
    REQUIRE(out.frames() == in.frames());
    double err = 0;
    for (std::size_t i = 2000; i + 2000 < in.frames(); ++i) err = std::max(err, double(std::abs(out.ch[0][i] - in.ch[0][i])));
    CHECK(err < 1e-5);
}

TEST_CASE("El tono no cambia al cambiar el tempo") {
    const int sr = 44100;
    const Buffer in = tone(440, 6, sr);
    for (double speed : {0.92, 1.05, 1.12}) {
        const Buffer out = stretch_constant(in, speed);
        const double f = peak_hz(out.ch[0], sr);
        INFO("velocidad " << speed << " -> " << f << " Hz");
        CHECK(std::abs(f - 440) < 1.0);
        CHECK(std::abs(static_cast<double>(out.frames()) - in.frames() / speed) < 2);
    }
}

TEST_CASE("El tempo resultante es el pedido") {
    const int sr = 44100;
    const Buffer in = clicks(125, 40, sr);
    const double target = 130;
    const Buffer out = stretch_constant(in, target / 125);
    const auto a = analyze_rhythm(to_mono(out), sr);
    INFO("medido " << a.grid.bpm);
    CHECK(std::abs(a.grid.bpm - target) < 0.05);
}

TEST_CASE("Sigue el mapa sin acumular deriva") {
    const int sr = 44100;
    const Buffer in = clicks(120, 30, sr);
    // Rampa: de velocidad 1 a 1,1 en 20 s. El golpe del original en t0 debe salir donde el mapa
    // inverso lo pone, con error menor que la tolerancia de búsqueda.
    auto map = [](double t) { return t + 0.05 * t * t / 20.0; };  // velocidad 1 + 0,1·t/20
    const Buffer out = stretch(in, map, 20.0);
    const auto env = onset_envelope(to_mono(out), sr);
    // Para cada golpe original en t0 (0,1 + k·0,5), su salida esperada es la raíz de map(t)=t0.
    int checked = 0, ok = 0;
    for (double t0 = 0.6; t0 < 20; t0 += 0.5) {
        double lo = 0, hi = 20;
        for (int it = 0; it < 60; ++it) (map(0.5 * (lo + hi)) < t0 ? lo : hi) = 0.5 * (lo + hi);
        const double t_exp = 0.5 * (lo + hi);
        if (t_exp > 19.5) break;
        // pico de la envolvente en ±40 ms
        double best = -1, tb = 0;
        for (std::size_t i = 0; i < env.full.size(); ++i) {
            const double t = env.time(i);
            if (std::abs(t - t_exp) < 0.04 && env.full[i] > best) best = env.full[i], tb = t;
        }
        ++checked;
        if (std::abs(tb - t_exp) < 0.015) ++ok;
    }
    INFO(ok << " de " << checked);
    CHECK(ok >= checked - 1);
}
