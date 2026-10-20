#include "mmn/stretch.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>
#include <vector>

namespace mmn {

Buffer stretch(const Buffer& in, const TimeMap& map, double out_seconds, const StretchOptions& opt) {
    Buffer out;
    out.sample_rate = in.sample_rate;
    const int sr = in.sample_rate;
    const auto n_out = static_cast<long>(std::llround(out_seconds * sr));
    out.ch.assign(in.channels(), std::vector<float>(static_cast<std::size_t>(std::max(0L, n_out)), 0.0f));
    if (n_out <= 0 || in.frames() == 0) return out;

    long N = static_cast<long>(std::lround(opt.frame_s * sr));
    N += N & 1;                        // par: con Hann periódica y solape del 50 % la suma es 1
    const long H = N / 2;              // salto de salida
    const long tol = static_cast<long>(std::lround(opt.tolerance_s * sr));
    const long len = static_cast<long>(in.frames());
    std::vector<float> win(static_cast<std::size_t>(N));
    for (long i = 0; i < N; ++i) win[i] = static_cast<float>(0.5 - 0.5 * std::cos(2 * std::numbers::pi * static_cast<double>(i) / static_cast<double>(N)));

    // Mono para la búsqueda (las decisiones se aplican igual a todos los canales).
    const std::vector<float> mono = to_mono(in);
    auto at = [&](long i) { return (i >= 0 && i < len) ? mono[i] : 0.0f; };

    long prev = -1;  // inicio del tramo de entrada usado en el paso anterior
    for (long m = 0; m * H < n_out + N; ++m) {
        const double t_out = static_cast<double>(m * H) / sr;
        const long nominal = static_cast<long>(std::lround(map(t_out) * sr));
        long best = nominal;
        if (prev >= 0) {
            // La continuación natural del tramo anterior empieza en prev + H. Se busca, cerca de la
            // posición nominal, el tramo cuya primera mitad más se parece a esa continuación.
            const long natural = prev + H;
            if (std::abs(natural - nominal) <= tol) best = natural;  // sin salto: reconstrucción exacta
            else {
                double best_c = -1e300;
                const long step = std::max(1L, H / 64);  // búsqueda gruesa y luego fina
                auto corr = [&](long cand) {
                    double c = 0;
                    for (long i = 0; i < H; i += 2) c += static_cast<double>(at(cand + i)) * at(natural + i);
                    return c;
                };
                for (long d = -tol; d <= tol; d += step) {
                    const double c = corr(nominal + d);
                    if (c > best_c) best_c = c, best = nominal + d;
                }
                const long centre = best;
                for (long d = -step; d <= step; ++d) {
                    const double c = corr(centre + d);
                    if (c > best_c) best_c = c, best = centre + d;
                }
            }
        }
        prev = best;
        const long o0 = m * H - H;  // el tramo m se centra en la salida m·H
        for (int c = 0; c < in.channels(); ++c) {
            const auto& src = in.ch[c];
            auto& dst = out.ch[c];
            for (long i = 0; i < N; ++i) {
                const long o = o0 + i, s = best - H + i;
                if (o < 0 || o >= n_out || s < 0 || s >= len) continue;
                dst[o] += src[s] * win[i];
            }
        }
    }
    return out;
}

Buffer stretch_constant(const Buffer& in, double speed, const StretchOptions& opt) {
    const double dur = in.seconds() / speed;
    return stretch(in, [speed](double t) { return t * speed; }, dur, opt);
}

}  // namespace mmn
