#include "doctest.h"
#include "mmn/key.hpp"

#include <cmath>
#include <numbers>
#include <vector>

using namespace mmn;

namespace {

/// Progresión I-IV-V-I con tonos de 4 armónicos, 2 s por acorde.
std::vector<float> progression(int tonic, bool minor, int sr) {
    const int third = minor ? 3 : 4;
    const std::vector<std::vector<int>> chords = {{0, third, 7}, {5, 5 + (minor ? 3 : 4), 12}, {7, 11, 14}, {0, third, 7}};
    std::vector<float> x;
    for (const auto& ch : chords)
        for (int i = 0; i < 2 * sr; ++i) {
            double v = 0;
            for (int n : ch) {
                const double f = 220.0 * std::pow(2.0, (tonic - 9 + n) / 12.0);
                for (int h = 1; h <= 4; ++h) v += std::sin(2 * std::numbers::pi * f * h * i / sr) / h;
            }
            x.push_back(static_cast<float>(0.1 * v));
        }
    return x;
}

}  // namespace

TEST_CASE("Camelot y nombres") {
    Key k;
    k.tonic = 9, k.minor = true;
    CHECK(k.camelot() == "8A");
    CHECK(k.name() == "A minor");
    k.tonic = 0, k.minor = false;
    CHECK(k.camelot() == "8B");
    k.tonic = 11, k.minor = false;
    CHECK(k.camelot() == "1B");
    k.tonic = 2, k.minor = true;
    CHECK(k.camelot() == "7A");
}

TEST_CASE("Lectura de tonalidades y puntuación MIREX") {
    CHECK(parse_key("C minor").tonic == 0);
    CHECK(parse_key("C minor").minor);
    CHECK(parse_key("F# major").tonic == 6);
    CHECK(parse_key("Bb minor").tonic == 10);
    CHECK(mirex_score(parse_key("A minor"), parse_key("A minor")) == 1.0);
    CHECK(mirex_score(parse_key("E minor"), parse_key("A minor")) == 0.5);
    CHECK(mirex_score(parse_key("C major"), parse_key("A minor")) == 0.3);
    CHECK(mirex_score(parse_key("A major"), parse_key("A minor")) == 0.2);
    CHECK(mirex_score(parse_key("F# major"), parse_key("A minor")) == 0.0);
}

TEST_CASE("Detecta la tonalidad de una progresión I-IV-V-I en las 24 tonalidades") {
    const int sr = 22050;
    int ok = 0;
    for (int minor = 0; minor < 2; ++minor)
        for (int t = 0; t < 12; ++t) {
            const auto x = progression(t, minor == 1, sr);
            const Key k = estimate_key(chromagram(x, sr));
            if (k.tonic == t && k.minor == (minor == 1)) ++ok;
            else INFO("esperado " << t << (minor ? "m" : "") << ", obtenido " << k.name());
        }
    CHECK(ok >= 22);  // las progresiones menores con V mayor pueden empatar con su relativa
}
