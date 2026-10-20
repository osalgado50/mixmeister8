// mmn/analysis.hpp — análisis rítmico: novedad, tempo, rejilla y compás.
#pragma once
#include <array>
#include <cstddef>
#include <span>
#include <vector>

namespace mmn {

/// Envolvente de novedad (ataques). value[t] corresponde al instante time(t).
struct OnsetEnvelope {
    double hop_s = 0;        ///< segundos entre muestras
    double offset_s = 0;     ///< instante de la muestra 0 de `full`
    double low_offset_s = 0; ///< instante de la muestra 0 de `low` (los graves responden antes)
    std::vector<float> full; ///< banda completa, normalizada a máx 1
    std::vector<float> low;  ///< graves (< 150 Hz), normalizada a máx 1
    /// Espectro log en bandas logarítmicas (30 Hz - 8 kHz), fila por frame: bands[t*n_bands + b].
    /// Sirve para medir cambios de timbre/armonía entre tiempos (compás, estructura).
    std::size_t n_bands = 0;
    std::vector<float> bands;
    double frame_offset_s = 0;  ///< instante del frame 0 de `bands`
    [[nodiscard]] double time(std::size_t t) const { return offset_s + static_cast<double>(t) * hop_s; }
    [[nodiscard]] double duration() const { return full.empty() ? 0.0 : time(full.size() - 1); }
};

OnsetEnvelope onset_envelope(std::span<const float> mono, int sample_rate);

struct TempoCandidate {
    double bpm = 0;
    double score = 0;   ///< evidencia sin prior
    double weighted = 0; ///< evidencia × prior de nivel métrico
};

struct TempoOptions {
    double min_bpm = 60, max_bpm = 200;
    double prior_center_bpm = 120;   ///< ya no lo usa el nivel métrico (regla aprendida); se conserva para quien lo quiera
    double prior_sigma_oct = 0.5;    ///< anchura del prior, en octavas
};

/// Candidatos de tempo global ordenados por `weighted`, descendente.
std::vector<TempoCandidate> tempo_candidates(const OnsetEnvelope& env, const TempoOptions& opt = {});

/// Rejilla de tempo constante.
struct BeatGrid {
    double bpm = 0;
    double first_beat_s = 0;   ///< primer tiempo >= 0
    int downbeat = 0;          ///< índice (0-3) del tiempo que abre compás, por el sonido (regla aprendida)
    long first_sounding_beat = 0;  ///< índice del primer tiempo con sonido (el compás 1)
    long last_sounding_beat = 0;   ///< índice del último tiempo con sonido
    double confidence = 0;     ///< pico frente a fondo, 0 = sin pulso
    [[nodiscard]] double period() const { return 60.0 / bpm; }
    [[nodiscard]] double beat_time(long k) const { return first_beat_s + static_cast<double>(k) * period(); }
};

/// Rasgos de fase de una rejilla (t0, periodo P), medias sobre todos sus tiempos:
/// [0-3] ataque en subgraves (30-90 Hz), graves (90-250), medios (250-2k), agudos (2k-8k);
/// [4-7] caída en esas mismas bandas (nivel a +30 ms menos nivel a +150 ms).
std::array<double, 8> phase_features(const OnsetEnvelope& env, double t0, double period);

/// Puntuación tiempo-frente-a-contratiempo: positiva si la rejilla en t0 está en el tiempo.
double phase_score(const OnsetEnvelope& env, double t0, double period);

/// Rasgos de compás: para cada posición j = 0..3 (tiempo k con k % 4 == j en la rejilla),
/// medias centradas entre posiciones de: [0-3] ataque en subgraves, graves, medios, agudos;
/// [4] cambio armónico (90 Hz-2 kHz, parte sostenida del tiempo, solo lo que aparece);
/// [5] novedad de compás (espectro de los 4 tiempos siguientes frente a los 4 anteriores);
/// [6] salto de nivel entre esos dos compases; [7] 1 si j es el primer tiempo que suena.
constexpr std::size_t kBarFeatures = 8;
std::array<std::array<double, kBarFeatures>, 4> bar_features(const OnsetEnvelope& env, double first_beat_s,
                                                             double period, long first_sounding_beat);

/// Candidato de nivel métrico (familia T, 2T, T/2, 3T/2, 2T/3 del mejor tempo) con sus rasgos:
/// [0] log de la fuerza del pulso bajo cada tiempo; [1] fuerza en el medio tiempo frente a la
/// del tiempo; [2] log de la coherencia de la rejilla frente a la del mejor candidato;
/// [3] x = log2(bpm/120); [4] x²; [5] log del pulso de graves.
constexpr std::size_t kLevelFeatures = 6;
struct LevelCandidate {
    double bpm = 0;
    std::array<double, kLevelFeatures> f{};
};
std::vector<LevelCandidate> level_candidates(const OnsetEnvelope& env, const std::vector<TempoCandidate>& cands,
                                             const TempoOptions& opt = {});

/// Afina periodo y fase alrededor de `bpm0` por coherencia de fase en toda la pista.
BeatGrid refine_grid(const OnsetEnvelope& env, double bpm0);

/// Ventanas de mezcla en frases de `phrase` tiempos (8 compases = 32), como MixMeister:
/// la entrada empieza en el primer compás que suena; la salida termina en la última frase
/// entera (contada desde la entrada) que cabe antes de que la pista deje de sonar, + 4 tiempos.
/// Contra los .mxm de la biblioteca (195 pistas): entrada exacta 60 % (±1 compás: 88 %);
/// salida exacta 77 %.
struct MixWindows {
    long entry_beat = 0;   ///< índice del tiempo donde empieza la ventana de entrada
    long exit_beat = 0;    ///< índice del tiempo donde empieza la ventana de salida
    int phrase = 32;       ///< longitud de cada ventana, en tiempos
};
MixWindows mix_windows(const BeatGrid& g, int phrase = 32);

/// Todo junto: envolvente → candidatos → rejilla → compás.
struct RhythmAnalysis {
    OnsetEnvelope env;
    std::vector<TempoCandidate> candidates;
    BeatGrid grid;
};
RhythmAnalysis analyze_rhythm(std::span<const float> mono, int sample_rate, const TempoOptions& opt = {});

}  // namespace mmn
