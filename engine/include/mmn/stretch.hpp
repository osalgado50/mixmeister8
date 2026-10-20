// mmn/stretch.hpp — cambio de tempo sin cambio de tono (WSOLA) guiado por un mapa de tiempos.
#pragma once
#include "mmn/audio.hpp"

#include <functional>

namespace mmn {

/// Mapa de tiempos: para un instante de la salida (s), el instante del original (s) que debe
/// sonar. Monótono creciente. La pendiente local es la velocidad (1,05 = 5 % más rápido).
using TimeMap = std::function<double(double)>;

struct StretchOptions {
    double frame_s = 0.040;      ///< ventana de análisis (~40 ms)
    double tolerance_s = 0.012;  ///< búsqueda de la mejor continuación (±12 ms)
};

/// WSOLA: tramos de `frame_s` con solape del 50 % y ventana de Hann; cada tramo se toma cerca
/// de map(t) donde mejor continúa la forma de onda del anterior. La posición no acumula
/// deriva: siempre se ancla a map(t), con error máximo `tolerance_s`.
/// Devuelve `out_seconds` de audio con los canales y la frecuencia de `in`.
Buffer stretch(const Buffer& in, const TimeMap& map, double out_seconds, const StretchOptions& opt = {});

/// Atajo: velocidad constante (1,0 = igual; 1,1 = 10 % más rápido y más corto).
Buffer stretch_constant(const Buffer& in, double speed, const StretchOptions& opt = {});

}  // namespace mmn
