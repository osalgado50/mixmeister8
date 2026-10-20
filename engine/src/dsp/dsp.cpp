#include "mmn/dsp.hpp"

#include <cmath>
#include <numbers>
#include <stdexcept>

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

void radix2(std::span<cfloat> x, const std::vector<std::size_t>& rev, const std::vector<cfloat>& tw, bool inv) {
    const std::size_t n = x.size();
    for (std::size_t i = 0; i < n; ++i)
        if (i < rev[i]) std::swap(x[i], x[rev[i]]);
    for (std::size_t len = 2; len <= n; len <<= 1) {
        const std::size_t step = n / len, h = len / 2;
        for (std::size_t s = 0; s < n; s += len)
            for (std::size_t k = 0; k < h; ++k) {
                cfloat w = tw[k * step];
                if (inv) w = std::conj(w);
                const cfloat a = x[s + k], b = x[s + k + h] * w;
                x[s + k] = a + b;
                x[s + k + h] = a - b;
            }
    }
}

}  // namespace

Fft::Fft(std::size_t n) : n_(n) {
    if (n < 2 || (n & (n - 1))) throw std::invalid_argument("FFT: tamaño no potencia de dos");
    rev_ = bitrev(n);
    tw_ = twiddles(n);
    rev_h_ = bitrev(n / 2);
    tw_h_ = twiddles(n / 2);
    tw_real_ = tw_;
}

void Fft::run(std::span<cfloat> x, bool inv) const {
    if (x.size() != n_) throw std::invalid_argument("FFT: tamaño distinto");
    radix2(x, rev_, tw_, inv);
}
void Fft::forward(std::span<cfloat> x) const { run(x, false); }
void Fft::inverse(std::span<cfloat> x) const { run(x, true); }

void Fft::real_forward(std::span<const float> in, std::span<cfloat> out) const {
    const std::size_t h = n_ / 2;
    if (in.size() != n_ || out.size() != h + 1) throw std::invalid_argument("FFT real: tamaños");
    std::vector<cfloat> z(h);
    for (std::size_t k = 0; k < h; ++k) z[k] = {in[2 * k], in[2 * k + 1]};
    if (h >= 2) radix2(z, rev_h_, tw_h_, false);
    // X[k] = E[k] + W^k O[k], con E = (Z[k] + conj(Z[h-k]))/2, O = (Z[k] - conj(Z[h-k]))/(2i)
    for (std::size_t k = 0; k <= h; ++k) {
        const cfloat zk = z[k % h], zc = std::conj(z[(h - k) % h]);
        const cfloat e = 0.5f * (zk + zc);
        const cfloat o = cfloat(0, -0.5f) * (zk - zc);
        out[k] = e + tw_real_[k] * o;
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
        for (std::size_t k = 0; k < s.bins; ++k) r[k] = std::abs(spec[k]);
    }
    return s;
}

}  // namespace mmn
