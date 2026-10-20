// mmn/mxm.hpp — lector del caché de análisis de MixMeister (.mxm, RIFF "MXM6").
// Solo lectura, para interoperar: recuperar el análisis viejo y medirse contra él.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace mmn {

struct MxmProfile {
    std::uint32_t version = 0;
    std::uint32_t sample_rate = 0;  ///< base de tiempo de TODAS las posiciones del perfil
    float bpm = 0;
    float confidence = 0;
    std::uint64_t region_begin = 0, region_end = 0, total_samples = 0;
    std::uint32_t bitrate = 0;
    int counter_width = 0;          ///< 4 u 8: las dos variantes que escribió MixMeister
    std::vector<std::vector<std::uint64_t>> arrays;  ///< [0] entrada, [1] salida, [2] reloj, [3] puntos de mezcla
    [[nodiscard]] double seconds(std::uint64_t s) const { return sample_rate ? static_cast<double>(s) / sample_rate : 0; }
};

struct Mxm {
    std::uint32_t format_version = 0;
    std::uint32_t info_rate = 0;
    std::uint64_t info_samples = 0;
    std::optional<MxmProfile> prof;
    std::vector<std::string> chunks;  ///< identificadores en orden de aparición
    [[nodiscard]] double duration_s() const { return info_rate ? static_cast<double>(info_samples) / info_rate : 0; }
};

/// Lanza std::runtime_error si el fichero no es un RIFF/MXM6.
Mxm read_mxm(const std::string& path);

}  // namespace mmn
