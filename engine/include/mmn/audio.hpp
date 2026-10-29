// mmn/audio.hpp — buffers de audio, lectura y escritura de ficheros.
#pragma once
#include <cstddef>
#include <span>
#include <string>
#include <vector>

namespace mmn {

/// Audio planar en float32, a la frecuencia nativa del fichero.
struct Buffer {
    int sample_rate = 0;
    std::vector<std::vector<float>> ch;  ///< un vector por canal, todos de igual longitud

    [[nodiscard]] int channels() const noexcept { return static_cast<int>(ch.size()); }
    [[nodiscard]] std::size_t frames() const noexcept { return ch.empty() ? 0 : ch[0].size(); }
    [[nodiscard]] double seconds() const noexcept {
        return sample_rate > 0 ? static_cast<double>(frames()) / sample_rate : 0.0;
    }
};

/// Lee MP3 o WAV (PCM 16/24/32 bits o float32); en macOS también M4A/AAC/ALAC, AIFF y FLAC
/// con el decodificador del sistema. Decide por el contenido, no por la extensión.
/// Lanza std::runtime_error si no puede.
Buffer read_audio(const std::string& path);

/// Muestras que hay que sumar a la línea de tiempo de un decodificador para estar en la de
/// MixMeister 7.8 (donde están las marcas de sus listas y sus .mxm). `system_decoder`: el de
/// Core Audio (AVAudioFile); si no, el de read_audio, que ya decodifica en la del original (→ 0).
/// Solo los MP3 difieren (ver audio.cpp).
long mixmeister_offset_frames(const std::string& path, bool system_decoder);

/// Escribe WAV PCM de 16 bits con limitación a [-1, 1].
void write_wav16(const std::string& path, const Buffer& b);

/// Media de los canales.
std::vector<float> to_mono(const Buffer& b);

/// Remuestreo con sinc enventanado (Kaiser), fase lineal. Conserva la duración:
/// la salida mide round(n * to / from) muestras.
std::vector<float> resample(std::span<const float> x, int from_rate, int to_rate);

}  // namespace mmn
