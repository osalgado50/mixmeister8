#include "mmn/dsp.hpp"

#include <cmath>
#include <numbers>
#include <stdexcept>

#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#endif

namespace mmn {
namespace {

std::vector<std::size_t> bitrev(std::size_t n) {
    std::vector<std::size_t> r(n, 0);
    std::size_t bits = 0;
    while ((std::size_t{1} << bits) < n) ++bits;
    for (std::size_t i = 0; i < n; ++i) {
        std::size_t v = 0;
        for (std::size_t b = 0; b < bits; ++b)
            if (i & (std::size_t{1} << b)) v |= std::size_t{1} << (bits - 1 - b);
        r[i] = v;
    }
    return r;
}

std::vector<cfloat> twiddles(std::size_t n) {
    std::vector<cfloat> t(n / 2 + 1);
    for (std::size_t k = 0; k < t.size(); ++k) {
        const double a = -2.0 * std::numbers::pi * static_cast<double>(k) / static_cast<double>(n);
        t[k] = {static_cast<float>(std::cos(a)), static_cast<float>(std::sin(a))};
    }
    return t;
}

/// Producto complejo explícito: el operador* de std::complex<float> llama a __mulsc3 (con
/// tratamiento de infinitos y NaN) y era el 70 % del tiempo de todo el análisis.
inline cfloat cmul(cfloat a, cfloat b) {
    return {a.real() * b.real() - a.imag() * b.imag(), a.real() * b.imag() + a.imag() * b.real()};
}

/// Giros por etapa, contiguos: etapa de longitud L ocupa [L/2 - 1, L - 1) con exp(-2πik/L).
std::vector<cfloat> stage_twiddles(std::size_t n) {
    std::vector<cfloat> t(n > 1 ? n - 1 : 1);
    for (std::size_t len = 2; len <= n; len <<= 1)
        for (std::size_t k = 0; k < len / 2; ++k) {
            const double a = -2.0 * std::numbers::pi * static_cast<double>(k) / static_cast<double>(len);
            t[len / 2 - 1 + k] = {static_cast<float>(std::cos(a)), static_cast<float>(std::sin(a))};
        }
    return t;
}

/// FFT in situ. `st` son los giros por etapa (stage_twiddles); con inv se usan conjugados.
/// Real e imaginario por separado: el operador* de std::complex<float> llama a __mulsc3 y
/// no vectoriza.
void radix2(std::span<cfloat> x, const std::vector<std::size_t>& rev, const std::vector<cfloat>& st, bool inv) {
    const std::size_t n = x.size();
    for (std::size_t i = 0; i < n; ++i)
        if (i < rev[i]) std::swap(x[i], x[rev[i]]);
    auto* d = reinterpret_cast<float*>(x.data());  // [re, im, re, im, ...] (garantizado por el estándar)
    const float sgn = inv ? -1.0f : 1.0f;
    for (std::size_t len = 2; len <= n; len <<= 1) {
        const std::size_t h = len / 2;
        const cfloat* w = &st[h - 1];
        for (std::size_t s = 0; s < n; s += len) {
            float* a = d + 2 * s;
            float* b = d + 2 * (s + h);
            for (std::size_t k = 0; k < h; ++k) {
                const float wr = w[k].real(), wi = sgn * w[k].imag();
                const float br = b[2 * k] * wr - b[2 * k + 1] * wi;
                const float bi = b[2 * k] * wi + b[2 * k + 1] * wr;
                const float ar = a[2 * k], ai = a[2 * k + 1];
                a[2 * k] = ar + br;
                a[2 * k + 1] = ai + bi;
                b[2 * k] = ar - br;
                b[2 * k + 1] = ai - bi;
            }
        }
    }
}

}  // namespace

#ifdef __APPLE__
/// vDSP: FFT del sistema (Accelerate), varias veces más rápida que la radix-2 propia. Mismas
/// convenciones: directa con e^{-i…}, inversa sin dividir por n.
struct Fft::Native {
    FFTSetup setup = nullptr;
    vDSP_Length log2n = 0;
    std::vector<float> re, im;
    ~Native() { if (setup) vDSP_destroy_fftsetup(setup); }
};
#else
struct Fft::Native {};
#endif

Fft::Fft(std::size_t n) : n_(n) {
    if (n < 2 || (n & (n - 1))) throw std::invalid_argument("FFT: tamaño no potencia de dos");
#ifdef __APPLE__
    if (n >= 4) {
        native_ = std::make_shared<Native>();
        while ((std::size_t{1} << native_->log2n) < n) ++native_->log2n;
        native_->setup = vDSP_create_fftsetup(native_->log2n, kFFTRadix2);
        native_->re.resize(n), native_->im.resize(n);
        if (native_->setup) return;
        native_.reset();
    }
#endif
    rev_ = bitrev(n);
    tw_ = stage_twiddles(n);
    rev_h_ = bitrev(n / 2);
    tw_h_ = stage_twiddles(n / 2);
    tw_real_ = twiddles(n);
}

void Fft::run(std::span<cfloat> x, bool inv) const {
    if (x.size() != n_) throw std::invalid_argument("FFT: tamaño distinto");
#ifdef __APPLE__
    if (native_) {
        auto& N = *native_;
        DSPSplitComplex z{N.re.data(), N.im.data()};
        vDSP_ctoz(reinterpret_cast<const DSPComplex*>(x.data()), 2, &z, 1, n_);
        vDSP_fft_zip(N.setup, &z, 1, N.log2n, inv ? kFFTDirection_Inverse : kFFTDirection_Forward);
        vDSP_ztoc(&z, 1, reinterpret_cast<DSPComplex*>(x.data()), 2, n_);
        return;
    }
#endif
    radix2(x, rev_, tw_, inv);
}
void Fft::forward(std::span<cfloat> x) const { run(x, false); }
void Fft::inverse(std::span<cfloat> x) const { run(x, true); }

void Fft::real_forward(std::span<const float> in, std::span<cfloat> out) const {
    const std::size_t h = n_ / 2;
    if (in.size() != n_ || out.size() != h + 1) throw std::invalid_argument("FFT real: tamaños");
#ifdef __APPLE__
    if (native_) {
        // vDSP_fft_zrip: pares (par, impar) como complejos; sale escalada ×2, con DC en re[0] y
        // Nyquist en im[0].
        auto& N = *native_;
        DSPSplitComplex z{N.re.data(), N.im.data()};
        vDSP_ctoz(reinterpret_cast<const DSPComplex*>(in.data()), 2, &z, 1, h);
        vDSP_fft_zrip(N.setup, &z, 1, N.log2n, kFFTDirection_Forward);
        out[0] = {0.5f * N.re[0], 0.0f};
        out[h] = {0.5f * N.im[0], 0.0f};
        for (std::size_t k = 1; k < h; ++k) out[k] = {0.5f * N.re[k], 0.5f * N.im[k]};
        return;
    }
#endif
    auto& z = scratch_;  // sin reservar memoria en cada marco
    z.resize(h);
    for (std::size_t k = 0; k < h; ++k) z[k] = {in[2 * k], in[2 * k + 1]};
    if (h >= 2) radix2(z, rev_h_, tw_h_, false);
    // X[k] = E[k] + W^k O[k], con E = (Z[k] + conj(Z[h-k]))/2, O = (Z[k] - conj(Z[h-k]))/(2i)
    for (std::size_t k = 0; k <= h; ++k) {
        const cfloat zk = z[k % h], zc = std::conj(z[(h - k) % h]);
        const cfloat e = 0.5f * (zk + zc);
        const cfloat o = cfloat(0, -0.5f) * (zk - zc);
        out[k] = e + cmul(tw_real_[k], o);
    }
}

std::vector<float> hann(std::size_t n) {
    std::vector<float> w(n);
    for (std::size_t i = 0; i < n; ++i)
        w[i] = static_cast<float>(0.5 - 0.5 * std::cos(2 * std::numbers::pi * static_cast<double>(i) / static_cast<double>(n)));
    return w;
}

Spectrogram stft_mag(std::span<const float> x, int sr, std::size_t n_fft, std::size_t hop) {
    Spectrogram s;
    s.n_fft = n_fft;
    s.hop = hop;
    s.bins = n_fft / 2 + 1;
    s.sample_rate = sr;
    s.frames = x.empty() ? 0 : x.size() / hop + 1;
    s.mag.assign(s.frames * s.bins, 0.0f);
    const Fft fft(n_fft);
    const auto w = hann(n_fft);
    std::vector<float> frame(n_fft);
    std::vector<cfloat> spec(s.bins);
    const long half = static_cast<long>(n_fft / 2);
    for (std::size_t t = 0; t < s.frames; ++t) {
        const long start = static_cast<long>(t * hop) - half;
        for (std::size_t i = 0; i < n_fft; ++i) {
            const long j = start + static_cast<long>(i);
            frame[i] = (j >= 0 && j < static_cast<long>(x.size())) ? x[j] * w[i] : 0.0f;
        }
        fft.real_forward(frame, spec);
        float* r = &s.mag[t * s.bins];
        for (std::size_t k = 0; k < s.bins; ++k)  // |z| sin hypot: no hay riesgo de desbordamiento aquí
            r[k] = std::sqrt(spec[k].real() * spec[k].real() + spec[k].imag() * spec[k].imag());
    }
    return s;
}

}  // namespace mmn
