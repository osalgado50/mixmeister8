// Efectos propios de MixMeister 8 (sustituyen a los AIR/NewBlue del original, que tienen licencia
// y no se pueden incluir). Procesado por bloques, en el sitio, sin reservar memoria al procesar.
// Todos los parámetros llegan normalizados 0..1; aquí se convierten a sus unidades.
#include "mmn_c.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;

inline double expmap(double v, double lo, double hi) { return lo * std::pow(hi / lo, std::clamp(v, 0.0, 1.0)); }
inline double lin(double v, double lo, double hi) { return lo + (hi - lo) * std::clamp(v, 0.0, 1.0); }

/// Filtro de estado variable (TPT, Zavalishin): paso bajo, banda y alto a la vez.
struct Svf {
    double ic1 = 0, ic2 = 0;
    void run(double x, double g, double k, double& lp, double& bp, double& hp) {
        const double a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
        const double v3 = x - ic2;
        const double v1 = a1 * ic1 + a2 * v3;
        const double v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2 * v1 - ic1;
        ic2 = 2 * v2 - ic2;
        lp = v2, bp = v1, hp = x - k * v1 - v2;
    }
};

struct Fx {
    int kind = 0;
    double sr = 44100;
    int ch = 2;
    std::array<float, 8> p{};        // parámetros normalizados
    std::array<double, 8> s{};       // valores suavizados
    double phase = 0;
    // retardo (flanger, stereoizer)
    std::vector<float> buf[2];
    std::size_t w = 0;
    double fb[2] = {0, 0};
    // phaser
    double ap[2][12] = {};
    double pfb[2] = {0, 0};
    // fuzz-wah, filter gate
    Svf svf[2];
    double gate = 1;
};

int count(int kind) {
    switch (kind) {
    case MMN_FX_FLANGER: return 4;
    case MMN_FX_PHASER: return 5;
    case MMN_FX_FUZZWAH: return 6;
    case MMN_FX_FILTERGATE: return 6;
    case MMN_FX_STEREOIZER: return 3;
    default: return 0;
    }
}

const float kDefaults[6][8] = {
    {},
    {0.35f, 0.6f, 0.6f, 0.5f},                 // flanger: rate, depth, feedback(0.5 = 0), mix
    {0.3f, 0.7f, 0.5f, 0.4f, 0.5f},            // phaser: rate, depth, feedback, stages, mix
    {0.4f, 0.4f, 0.5f, 0.35f, 0.7f, 1.0f},     // fuzz-wah: drive, freq, reso, lfo rate, lfo depth, mix
    {0.55f, 0.3f, 0.0f, 0.5f, 0.0f, 1.0f},     // filter gate: cutoff, reso, type, rate, depth, mix
    {0.5f, 0.2f, 1.0f},                        // stereoizer: width (0.5 = 100 %), haas, mix
};

void process(Fx& f, float* l, float* r, int n) {
    float* io[2] = {l, r ? r : l};
    const int nc = r ? 2 : 1;
    // Suavizado de parámetros por bloque (evita chasquidos al automatizar).
    const double a = 1 - std::exp(-static_cast<double>(n) / (0.02 * f.sr));
    for (int i = 0; i < 8; ++i) f.s[i] += (f.p[i] - f.s[i]) * a;
    const auto& s = f.s;

    switch (f.kind) {
    case MMN_FX_FLANGER: {
        const double rate = expmap(s[0], 0.03, 6.0), depth = s[1], feedback = lin(s[2], -0.95, 0.95), mix = s[3];
        const double maxd = 0.008 * f.sr, mind = 0.0002 * f.sr;
        const std::size_t L = f.buf[0].size();
        for (int i = 0; i < n; ++i) {
            f.phase += rate / f.sr;
            if (f.phase >= 1) f.phase -= 1;
            for (int c = 0; c < nc; ++c) {
                const double ph = f.phase + (c ? 0.25 : 0);
                const double lfo = 0.5 - 0.5 * std::cos(2 * kPi * ph);
                const double d = mind + (maxd - mind) * depth * lfo;
                double rp = static_cast<double>(f.w) - d;
                while (rp < 0) rp += static_cast<double>(L);
                const std::size_t i0 = static_cast<std::size_t>(rp) % L, i1 = (i0 + 1) % L;
                const double fr = rp - std::floor(rp);
                const double del = f.buf[c][i0] * (1 - fr) + f.buf[c][i1] * fr;
                const double x = io[c][i];
                f.buf[c][f.w] = static_cast<float>(x + feedback * del);
                io[c][i] = static_cast<float>((1 - mix) * x + mix * 0.5 * (x + del));
            }
            f.w = (f.w + 1) % L;
        }
        break;
    }
    case MMN_FX_PHASER: {
        const double rate = expmap(s[0], 0.03, 6.0), depth = s[1], feedback = lin(s[2], 0, 0.92), mix = s[4];
        const int stages = 2 * (1 + std::clamp(static_cast<int>(s[3] * 6), 0, 5));   // 2..12 (6 pasos)
        for (int i = 0; i < n; ++i) {
            f.phase += rate / f.sr;
            if (f.phase >= 1) f.phase -= 1;
            for (int c = 0; c < nc; ++c) {
                const double ph = f.phase + (c ? 0.25 : 0);
                const double lfo = 0.5 - 0.5 * std::cos(2 * kPi * ph);
                const double fc = expmap(lfo * depth, 180, 180 + 6000 * std::max(0.05, depth));
                const double t = std::tan(kPi * std::min(fc, f.sr * 0.45) / f.sr);
                const double coef = (t - 1) / (t + 1);
                const double x = io[c][i];
                double y = x + feedback * f.pfb[c];
                for (int k = 0; k < stages; ++k) {
                    const double out = coef * y + f.ap[c][k];
                    f.ap[c][k] = y - coef * out;
                    y = out;
                }
                f.pfb[c] = y;
                io[c][i] = static_cast<float>((1 - mix) * x + mix * 0.5 * (x + y));
            }
        }
        break;
    }
    case MMN_FX_FUZZWAH: {
        const double drive = std::pow(10, lin(s[0], 0, 36) / 20), q = lin(s[2], 0.7, 12), lrate = s[3] < 0.02 ? 0 : expmap(s[3], 0.1, 8);
        const double ldepth = s[4], mix = s[5];
        const double norm = std::tanh(drive);
        for (int i = 0; i < n; ++i) {
            if (lrate > 0) { f.phase += lrate / f.sr; if (f.phase >= 1) f.phase -= 1; }
            const double lfo = lrate > 0 ? (0.5 - 0.5 * std::cos(2 * kPi * f.phase)) : 0.5;
            const double pos = std::clamp(s[1] + (lfo - 0.5) * ldepth, 0.0, 1.0);
            const double fc = expmap(pos, 350, 2600);
            const double g = std::tan(kPi * fc / f.sr), k = 1 / q;
            for (int c = 0; c < nc; ++c) {
                const double x = io[c][i];
                const double fz = std::tanh(drive * x) / norm;
                double lp, bp, hp;
                f.svf[c].run(fz, g, k, lp, bp, hp);
                const double y = bp * k * (1.0 + 0.25 * std::sqrt(q));   // banda normalizada (pico ≈ 1) con algo de realce
                io[c][i] = static_cast<float>((1 - mix) * x + mix * y);
            }
        }
        break;
    }
    case MMN_FX_FILTERGATE: {
        const double fc = expmap(s[0], 30, 18000), q = lin(s[1], 0.6, 14), rate = expmap(s[3], 0.25, 16), depth = s[4], mix = s[5];
        const int type = std::clamp(static_cast<int>(s[2] * 3), 0, 2);
        const double g = std::tan(kPi * std::min(fc, f.sr * 0.45) / f.sr), k = 1 / q;
        const double slew = 1 - std::exp(-1.0 / (0.003 * f.sr));
        for (int i = 0; i < n; ++i) {
            f.phase += rate / f.sr;
            if (f.phase >= 1) f.phase -= 1;
            const double target = f.phase < 0.5 ? 1.0 : 1.0 - depth;
            f.gate += (target - f.gate) * slew;
            for (int c = 0; c < nc; ++c) {
                const double x = io[c][i];
                double lp, bp, hp;
                f.svf[c].run(x, g, k, lp, bp, hp);
                const double y = (type == 0 ? lp : type == 1 ? bp : hp) * f.gate;
                io[c][i] = static_cast<float>((1 - mix) * x + mix * y);
            }
        }
        break;
    }
    case MMN_FX_STEREOIZER: {
        if (nc < 2) break;
        const double width = s[0] * 2, haas = s[1] * 0.02 * f.sr, mix = s[2];
        const std::size_t L = f.buf[0].size();
        for (int i = 0; i < n; ++i) {
            const double L0 = io[0][i], R0 = io[1][i];
            const double m = 0.5 * (L0 + R0);
            double side = 0.5 * (L0 - R0);
            f.buf[0][f.w] = static_cast<float>(side);
            std::size_t rp = (f.w + L - static_cast<std::size_t>(haas)) % L;
            const double delayed = f.buf[0][rp];
            side = side * width + delayed * 0.35 * std::min(1.0, width);
            f.w = (f.w + 1) % L;
            io[0][i] = static_cast<float>((1 - mix) * L0 + mix * (m + side));
            io[1][i] = static_cast<float>((1 - mix) * R0 + mix * (m - side));
        }
        break;
    }
    default: break;
    }
}

}  // namespace

struct mmn_fx { Fx f; };

extern "C" {

int mmn_fx_param_count(int kind) { return count(kind); }

float mmn_fx_param_default(int kind, int param) {
    if (kind < 1 || kind > 5 || param < 0 || param >= 8) return 0;
    return kDefaults[kind][param];
}

mmn_fx* mmn_fx_new(int kind, double sample_rate, int channels) {
    if (count(kind) == 0) return nullptr;
    auto* x = new mmn_fx;
    x->f.kind = kind;
    x->f.sr = sample_rate > 0 ? sample_rate : 44100;
    x->f.ch = channels;
    for (int i = 0; i < 8; ++i) x->f.p[static_cast<std::size_t>(i)] = kDefaults[kind][i], x->f.s[static_cast<std::size_t>(i)] = kDefaults[kind][i];
    const std::size_t len = static_cast<std::size_t>(x->f.sr * 0.05) + 4;
    x->f.buf[0].assign(len, 0.f);
    x->f.buf[1].assign(len, 0.f);
    return x;
}

void mmn_fx_free(mmn_fx* x) { delete x; }

void mmn_fx_set(mmn_fx* x, int param, float value) {
    if (x && param >= 0 && param < 8) x->f.p[static_cast<std::size_t>(param)] = std::clamp(value, 0.f, 1.f);
}

float mmn_fx_get(mmn_fx* x, int param) {
    return (x && param >= 0 && param < 8) ? x->f.p[static_cast<std::size_t>(param)] : 0.f;
}

void mmn_fx_reset(mmn_fx* x) {
    if (!x) return;
    auto& f = x->f;
    for (auto& b : f.buf) std::fill(b.begin(), b.end(), 0.f);
    f.w = 0;
    f.phase = 0;
    f.fb[0] = f.fb[1] = 0;
    f.pfb[0] = f.pfb[1] = 0;
    for (auto& a : f.ap) for (double& v : a) v = 0;
    f.svf[0] = f.svf[1] = Svf{};
    f.gate = 1;
}

void mmn_fx_process(mmn_fx* x, float* left, float* right, int frames) {
    if (x && left && frames > 0) process(x->f, left, right, frames);
}

}  // extern "C"
