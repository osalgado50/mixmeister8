// mmn/mmp.hpp — sesiones de MixMeister (.mmp, RIFF "MXMP"). Lectura, para interoperar.
#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace mmn {

struct MmpTrack {
    std::string path;             ///< ruta tal como la guardó MixMeister (a menudo C:\...)
    std::string transition_in;    ///< "Beatmix Full", "Simple Cut"… (vacío en la primera)
    std::string transition_out;   ///< vacío en la última
    std::array<std::uint8_t, 16> hash{};  ///< identifica el audio (casa con el del .mxm)
    std::size_t tempo_markers = 0;        ///< marcadores de tiempo guardados (TKTM/TRKM)
};

/// Lanza std::runtime_error si no es un RIFF/MXMP.
std::vector<MmpTrack> read_mmp(const std::string& path);

/// Encuentra el audio de una pista aunque la ruta guardada ya no exista (otra máquina, otro
/// disco, Windows): primero la ruta tal cual; si no, el mismo nombre de fichero (sin distinguir
/// mayúsculas) dentro de `search_dirs`, recursivamente. Vacío si no aparece.
std::string resolve_track(const std::string& stored, const std::vector<std::string>& search_dirs);

}  // namespace mmn
