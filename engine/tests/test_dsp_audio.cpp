#include "doctest.h"
#include "mmn/audio.hpp"
#include "mmn/dsp.hpp"

#include <cmath>
#include <cstdio>
#include <filesystem>
#include <numbers>
#include <random>

using namespace mmn;

TEST_CASE("FFT compleja coincide con la DFT directa") {
    for (std::size_t n : {2u, 8u, 64u, 1024u}) {
        std::mt19937 rng(7);
        std::normal_distribution<float> nd;
        std::vector<cfloat> x(n), X(n);
        for (auto& v : x) v = {nd(rng), nd(rng)};
        for (std::size_t k = 0; k < n; ++k) {
            std::complex<double> s = 0;
            for (std::size_t t = 0; t < n; ++t)
                s += std::complex<double>(x[t]) * std::polar(1.0, -2 * std::numbers::pi * double(k * t) / n);
            X[k] = cfloat(s);
        }
        auto y = x;
        Fft(n).forward(y);
        double err = 0, ref = 0;
        for (std::size_t k = 0; k < n; ++k) err = std::max(err, double(std::abs(y[k] - X[k]))), ref = std::max(ref, double(std::abs(X[k])));
        CHECK(err / ref < 2e-5);
        Fft(n).inverse(y);
        double rt = 0;
        for (std::size_t t = 0; t < n; ++t) rt = std::max(rt, double(std::abs(y[t] / float(n) - x[t])));
        CHECK(rt < 1e-4);
    }
}

TEST_CASE("FFT real coincide con la compleja") {
    const std::size_t n = 2048;
    std::mt19937 rng(3);
    std::uniform_real_distribution<float> u(-1, 1);
    std::vector<float> x(n);
    for (auto& v : x) v = u(rng);
    std::vector<cfloat> c(x.begin(), x.end()), r(n / 2 + 1);
    const Fft f(n);
    f.forward(c);
    f.real_forward(x, r);
    double err = 0;
    for (std::size_t k = 0; k <= n / 2; ++k) err = std::max(err, double(std::abs(r[k] - c[k])));
    CHECK(err < 1e-3);
}

TEST_CASE("El remuestreo conserva un tono y la duración") {
    const int from = 48000, to = 44100;
    std::vector<float> x(from);
    for (std::size_t i = 0; i < x.size(); ++i) x[i] = std::sin(2 * std::numbers::pi * 1000.0 * i / from);
    const auto y = resample(x, from, to);
    CHECK(y.size() == static_cast<std::size_t>(to));
    double err = 0;
    for (std::size_t i = 2000; i < y.size() - 2000; ++i)
        err = std::max(err, std::abs(y[i] - std::sin(2 * std::numbers::pi * 1000.0 * i / to)));
    CHECK(err < 2e-3);
}

TEST_CASE("WAV: escribir y leer da lo mismo a 16 bits") {
    Buffer b;
    b.sample_rate = 22050;
    b.ch.assign(2, std::vector<float>(1000));
    for (std::size_t i = 0; i < 1000; ++i) b.ch[0][i] = 0.5f * std::sin(i * 0.01f), b.ch[1][i] = -b.ch[0][i];
    // En la carpeta temporal: la actual puede no admitir escritura (p. ej. "/").
    const std::string p = (std::filesystem::temp_directory_path() / "mmn_test_rt.wav").string();
    write_wav16(p, b);
    const Buffer r = read_audio(p);
    std::remove(p.c_str());
    REQUIRE(r.channels() == 2);
    REQUIRE(r.frames() == 1000);
    CHECK(r.sample_rate == 22050);
    double err = 0;
    for (std::size_t i = 0; i < 1000; ++i) err = std::max(err, double(std::abs(r.ch[1][i] - b.ch[1][i])));
    CHECK(err < 1.0 / 16384);
}
