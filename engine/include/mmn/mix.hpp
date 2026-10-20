// mmn/mix.hpp — transición entre dos pistas cuadrada a tiempo y a compás.
#pragma once
#include "mmn/analysis.hpp"
#include "mmn/audio.hpp"

#include <vector>

namespace mmn {

/// Lo que el mezclador necesita de cada pista.
struct Track {
    Buffer audio;
    BeatGrid grid;
    MixWindows windows;
};

/// Analiza una pista leída de disco (ritmo + ventanas).
Track load_track(const std::string& path);

struct TransitionInfo {
    double start_s = 0;      ///< instante de la salida donde empieza el solape
    double length_s = 0;     ///< duración del solape
    double total_s = 0;      ///< duración total de la mezcla
    double bpm_from = 0, bpm_to = 0;
};

/// Una sesión: cada pista entra por su ventana de entrada mientras la anterior sale por su
/// ventana de salida (mismas reglas que render_transition), todo sobre una sola línea de
/// tiempo. `marks` recibe, por pista, el instante de la salida donde empieza a sonar.
struct SessionInfo {
    std::vector<double> starts;          ///< por pista: inicio en la mezcla (s)
    std::vector<TransitionInfo> joins;   ///< por transición
    double total_s = 0;
};
Buffer render_session(const std::vector<Track>& tracks, SessionInfo* info = nullptr);

/// A suena a su tempo hasta el inicio de su ventana de salida. Durante `phrase` tiempos A (su
/// ventana de salida) y B (su ventana de entrada) suenan juntas, tiempo con tiempo, con el
/// tempo en rampa lineal de A a B y volumen cruzado a potencia constante. Después B sigue a su
/// tempo. La salida va a la frecuencia de A (B se remuestrea si hace falta).
Buffer render_transition(const Track& a, const Track& b, TransitionInfo* info = nullptr);

}  // namespace mmn
