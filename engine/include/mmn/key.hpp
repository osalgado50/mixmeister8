// mmn/key.hpp — tonalidad global: cromagrama, perfiles y notación Camelot.
#pragma once
#include <array>
#include <span>
#include <string>

namespace mmn {

using Chroma = std::array<double, 12>;  ///< energía por clase de altura, C = 0 … B = 11

/// Cromagrama medio de toda la pista. FFT de ~186 ms, 65 Hz - 4 kHz, amplitud log, cada
/// bin repartido entre las dos clases de altura más cercanas (A4 = 440 Hz). Normalizado a
/// máx 1.
Chroma chromagram(std::span<const float> mono, int sample_rate);

/// Perfiles de tonalidad: peso de cada grado (0 = tónica) en mayor y en menor.
struct KeyProfiles {
    Chroma major{}, minor{};
};
KeyProfiles profiles_krumhansl();  ///< Krumhansl & Kessler (1982)
KeyProfiles profiles_temperley();  ///< Temperley (1999)
KeyProfiles profiles_giantsteps(); ///< aprendidos de GiantSteps Key (música electrónica)
KeyProfiles profiles_default();    ///< los que usa el motor: profiles_giantsteps()

struct Key {
    int tonic = 0;        ///< 0 = C … 11 = B
    bool minor = false;
    double score = 0;     ///< correlación con el perfil ganador
    double margin = 0;    ///< ventaja sobre la segunda tonalidad: confianza
    [[nodiscard]] std::string name() const;     ///< "A minor", "F# major"
    [[nodiscard]] std::string camelot() const;  ///< "8A", "2B"
};

/// Tonalidad por correlación del cromagrama con los 24 perfiles rotados.
Key estimate_key(const Chroma& c, const KeyProfiles& p = profiles_default());

/// Lee "C minor", "F# major", "Bb minor"… (formato de GiantSteps). tonic = -1 si no puede.
Key parse_key(const std::string& s);

/// Puntuación MIREX: 1 igual; 0,5 quinta (mismo modo, ±7 semitonos); 0,3 relativa; 0,2 paralela.
double mirex_score(const Key& estimated, const Key& reference);

}  // namespace mmn
