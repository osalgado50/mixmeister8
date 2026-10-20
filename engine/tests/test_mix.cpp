// Transición entre dos pistas: tempo al principio y al final, y golpes alineados en el solape.
#include "doctest.h"
#include "mmn/mix.hpp"

#include <cmath>
#include <numbers>
#include <random>

using namespace mmn;

namespace {
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

Track make(double bpm, double seconds, unsigned seed) {
    Track t;
    t.audio.sample_rate = 44100;
    t.audio.ch.assign(1, groove(bpm, 0.2, seconds, 44100, 0, 0.01, 0, seed));
    t.grid = analyze_rhythm(t.audio.ch[0], 44100).grid;
    t.windows = mix_windows(t.grid);
    return t;
}

Buffer slice(const Buffer& b, double from, double to) {
    Buffer s;
    s.sample_rate = b.sample_rate;
    const auto i0 = static_cast<std::size_t>(from * b.sample_rate), i1 = std::min(b.frames(), static_cast<std::size_t>(to * b.sample_rate));
    for (const auto& c : b.ch) s.ch.emplace_back(c.begin() + static_cast<long>(i0), c.begin() + static_cast<long>(i1));
    return s;
}

}  // namespace

TEST_CASE("Transición 124 → 130: tempo de cada lado y golpes alineados en el solape") {
    const Track a = make(124, 75, 1), b = make(130, 75, 2);
    REQUIRE(std::abs(a.grid.bpm - 124) < 0.02);
    REQUIRE(std::abs(b.grid.bpm - 130) < 0.02);
    TransitionInfo info;
    const Buffer out = render_transition(a, b, &info);
    CHECK(std::abs(info.length_s - 32 * 60.0 / 127.0) < 0.2);  // rampa: entre 32 tiempos a 124 y a 130
    const auto head = analyze_rhythm(slice(out, 0, info.start_s).ch[0], 44100).grid;
    const auto tail = analyze_rhythm(slice(out, info.start_s + info.length_s, info.total_s).ch[0], 44100).grid;
    INFO("principio " << head.bpm << ", final " << tail.bpm);
    CHECK(std::abs(head.bpm - 124) < 0.05);
    CHECK(std::abs(tail.bpm - 130) < 0.05);
    // En el solape, los ataques fuertes deben caer en los tiempos (bombo) o medios tiempos
    // (charles) de la rampa. Si las dos pistas no estuvieran cuadradas, saldrían en medio.
    const auto env = onset_envelope(slice(out, info.start_s, info.start_s + info.length_s).ch[0], 44100);
    const double ta = 124, tb = 130, L = 32;
    auto beat_time = [&](double beta) { return 60.0 * L / (tb - ta) * std::log((ta + (tb - ta) * beta / L) / ta); };
    int peaks = 0, aligned = 0;
    for (std::size_t i = 1; i + 1 < env.full.size(); ++i) {
        if (env.full[i] < 0.3 || env.full[i] < env.full[i - 1] || env.full[i] < env.full[i + 1]) continue;
        ++peaks;
        double best = 1e9;
        for (int k = 0; k <= 64; ++k) best = std::min(best, std::abs(env.time(i) - beat_time(0.5 * k)));
        if (best < 0.015) ++aligned;
    }
    INFO(aligned << " de " << peaks << " ataques sobre un tiempo o medio tiempo");
    CHECK(peaks >= 28);
    CHECK(aligned >= peaks * 9 / 10);
}
