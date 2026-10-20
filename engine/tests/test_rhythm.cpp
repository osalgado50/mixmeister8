// Ritmo sobre señales sintéticas con verdad conocida.
#include "doctest.h"
#include "mmn/analysis.hpp"

#include <cmath>
#include <numbers>
#include <random>

using namespace mmn;

namespace {

/// Bombo + charles: bombo en cada tiempo, charles en las corcheas, y un acorde que
/// cambia en el primer tiempo de cada compás. `jitter_ms` desplaza cada golpe al azar.
std::vector<float> groove(double bpm, double first, double seconds, int sr, double jitter_ms = 0, double noise = 0.02,
                          int bar_phase = 0, unsigned seed = 1) {
    std::vector<float> x(static_cast<std::size_t>(seconds * sr), 0.0f);
    std::mt19937 rng(seed);
    std::normal_distribution<double> jit(0, jitter_ms / 1000.0);
    std::normal_distribution<float> nz(0, static_cast<float>(noise));
    const double P = 60 / bpm;
    auto hit = [&](double t, double f0, double decay, float amp, bool tonal) {
        const long s0 = std::lround(t * sr);
        for (long i = 0; i < static_cast<long>(0.25 * sr); ++i) {
            const long j = s0 + i;
            if (j < 0 || j >= static_cast<long>(x.size())) continue;
            const double tt = static_cast<double>(i) / sr;
            const double env = std::exp(-tt / decay);
            const double ph = tonal ? 2 * std::numbers::pi * f0 * tt : 2 * std::numbers::pi * f0 * tt * (1 - 0.5 * tt / 0.25);
            x[j] += amp * static_cast<float>(env * std::sin(ph));
        }
    };
    std::uniform_real_distribution<float> u(-1, 1);
    long k = 0;
    for (double t = first; t < seconds; t += P, ++k) {
        const double tj = t + jit(rng);
        hit(tj, 60, 0.08, 0.9f, false);  // bombo
        // charles: ruido corto en la corchea
        for (double h : {tj, tj + P / 2}) {
            const long s0 = std::lround(h * sr);
            for (long i = 0; i < static_cast<long>(0.03 * sr); ++i)
                if (s0 + i >= 0 && s0 + i < static_cast<long>(x.size()))
                    x[s0 + i] += 0.15f * u(rng) * std::exp(-static_cast<float>(i) / (0.008f * sr));
        }
        if (((k - bar_phase) % 4 + 4) % 4 == 0) {  // cambio de bajo/acorde al abrir compás
            const double root = 55.0 * std::pow(2.0, ((k / 4) % 3) * 3 / 12.0);
            hit(tj, root, 1.2, 0.5f, true);
            hit(tj, root * 3, 1.0, 0.15f, true);
        }
    }
    for (auto& v : x) v += nz(rng);
    return x;
}

}  // namespace

TEST_CASE("Tempo y fase exactos en un groove limpio") {
    const int sr = 44100;
    for (double bpm : {120.0, 128.0, 133.333, 174.0}) {
        const double first = 0.137;
        const auto x = groove(bpm, first, 60, sr);
        const auto a = analyze_rhythm(x, sr);
        INFO("bpm real " << bpm << ", medido " << a.grid.bpm);
        CHECK(std::abs(a.grid.bpm - bpm) < 0.01);
        // fase: el primer tiempo medido cae sobre un tiempo real (módulo periodo)
        const double P = 60 / bpm;
        double d = std::fmod(a.grid.first_beat_s - first + 10 * P, P);
        if (d > P / 2) d -= P;
        INFO("desfase " << d * 1000 << " ms");
        CHECK(std::abs(d) < 0.002);  // ±2 ms: calibrado de kOnsetLag y kLowOnsetLag
    }
}

TEST_CASE("Tempo estable con temblor humano de 8 ms y ruido") {
    const int sr = 44100;
    const auto x = groove(126.0, 0.4, 90, sr, 8.0, 0.05, 0, 9);
    const auto a = analyze_rhythm(x, sr);
    CHECK(std::abs(a.grid.bpm - 126.0) < 0.02);
}

TEST_CASE("Funciona a 22050 y 48000 Hz") {
    for (int sr : {22050, 48000}) {
        const auto x = groove(124.0, 0.25, 45, sr);
        const auto a = analyze_rhythm(x, sr);
        INFO("sr " << sr << " -> " << a.grid.bpm);
        CHECK(std::abs(a.grid.bpm - 124.0) < 0.01);
    }
}

TEST_CASE("El compás 1 es el primer tiempo que suena, tras un silencio o una entrada suave") {
    const int sr = 44100;
    const double bpm = 128, P = 60 / bpm;
    for (int lead : {0, 1, 2, 3, 6}) {
        // silencio de `lead` tiempos y después el groove
        auto x = groove(bpm, 0.15 + lead * P, 50, sr, 0, 0.0, 0);
        for (std::size_t i = 0; i < static_cast<std::size_t>((0.15 + lead * P - 0.05) * sr); ++i) x[i] *= 0.02f;
        const auto a = analyze_rhythm(x, sr);
        const long k = std::lround((0.15 + lead * P - a.grid.first_beat_s) / P);
        INFO("lead " << lead << ": compás en " << a.grid.downbeat << ", primer tiempo " << a.grid.first_sounding_beat
                     << ", esperado " << k);
        CHECK(a.grid.first_sounding_beat == k);
        CHECK(a.grid.downbeat == k % 4);
    }
}

TEST_CASE("Sin pulso, confianza baja") {
    const int sr = 44100;
    std::mt19937 rng(5);
    std::normal_distribution<float> nd(0, 0.1f);
    std::vector<float> x(30 * sr);
    for (auto& v : x) v = nd(rng);
    const auto a = analyze_rhythm(x, sr);
    const auto g = analyze_rhythm(groove(128, 0.1, 30, sr), sr);
    INFO("ruido " << a.grid.confidence << " groove " << g.grid.confidence);
    CHECK(a.grid.confidence < 0.25 * g.grid.confidence);
}
