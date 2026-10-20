// mmn/dsp.hpp — FFT, ventanas y espectrograma.
#pragma once
#include <complex>
#include <cstddef>
#include <span>
#include <vector>

namespace mmn {

using cfloat = std::complex<float>;

/// FFT radix-2 iterativa. Tamaño potencia de dos. Sin normalizar en ninguna dirección.
class Fft {
public:
    explicit Fft(std::size_t n);
    [[nodiscard]] std::size_t size() const noexcept { return n_; }
    void forward(std::span<cfloat> x) const;   ///< in situ, exp(-i...)
    void inverse(std::span<cfloat> x) const;   ///< in situ, exp(+i...), sin dividir por n
    /// Transformada de una señal real de n muestras: n/2+1 bins.
    void real_forward(std::span<const float> in, std::span<cfloat> out) const;

private:
    void run(std::span<cfloat> x, bool inv) const;
    std::size_t n_;
    std::vector<cfloat> tw_;           // giros de tamaño n
    std::vector<std::size_t> rev_;     // permutación bit-reversal para n
    std::vector<cfloat> tw_real_;      // giros de post-proceso real (n)
    std::vector<std::size_t> rev_h_;   // permutación para n/2
    std::vector<cfloat> tw_h_;         // giros para n/2
};

/// Ventana de Hann periódica.
std::vector<float> hann(std::size_t n);

/// Espectrograma de magnitud: frames × (n_fft/2+1). Frame t empieza en t*hop
/// (relleno con ceros por delante n_fft/2 para centrar el frame en t*hop).
struct Spectrogram {
    std::size_t n_fft = 0, hop = 0, bins = 0, frames = 0;
    int sample_rate = 0;
    std::vector<float> mag;  ///< fila t: mag[t*bins + k]
    [[nodiscard]] const float* row(std::size_t t) const { return &mag[t * bins]; }
    [[nodiscard]] double frame_time(std::size_t t) const { return static_cast<double>(t * hop) / sample_rate; }
};
Spectrogram stft_mag(std::span<const float> x, int sample_rate, std::size_t n_fft, std::size_t hop);

}  // namespace mmn
