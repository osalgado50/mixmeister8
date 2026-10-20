// mmn — línea de comandos del motor MMStudio Next.
#include "mmn/analysis.hpp"
#include "mmn/audio.hpp"
#include "mmn/mxm.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <tuple>
#include <vector>

using namespace mmn;

namespace {

int usage() {
    std::puts(
        "mmn analyze [--json] fichero...     tempo, primer tiempo y compás\n"
        "mmn mxm fichero.mxm                 lee un análisis de MixMeister\n"
        "mmn compare audio fichero.mxm       nuevo frente a MixMeister\n"
        "mmn tsv audio fichero.mxm           una línea TSV para la suite de validación");
    return 2;
}

std::string base(const std::string& p) {
    const auto s = p.find_last_of('/');
    return s == std::string::npos ? p : p.substr(s + 1);
}

struct Result {
    RhythmAnalysis a;
    double seconds = 0, elapsed_ms = 0;
};

Result run(const std::string& path) {
    const auto t0 = std::chrono::steady_clock::now();
    const Buffer b = read_audio(path);
    const auto mono = to_mono(b);
    Result r;
    r.seconds = b.seconds();
    // Solo para experimentar: MMN_PRIOR_CENTER y MMN_PRIOR_SIGMA cambian el prior de nivel.
    TempoOptions opt;
    if (const char* c = std::getenv("MMN_PRIOR_CENTER")) opt.prior_center_bpm = std::atof(c);
    if (const char* c = std::getenv("MMN_PRIOR_SIGMA")) opt.prior_sigma_oct = std::atof(c);
    r.a = analyze_rhythm(mono, b.sample_rate, opt);
    r.elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    return r;
}

/// Distancia (en tiempos, con signo, -0.5..0.5) del instante t al tiempo más cercano de la rejilla,
/// y el índice de ese tiempo.
std::pair<double, long> beat_offset(const BeatGrid& g, double t) {
    const double k = (t - g.first_beat_s) / g.period();
    const long kn = std::lround(k);
    return {k - static_cast<double>(kn), kn};
}

int cmd_analyze(int argc, char** argv) {
    bool json = false;
    std::vector<std::string> files;
    for (int i = 2; i < argc; ++i)
        if (!std::strcmp(argv[i], "--json")) json = true;
        else files.emplace_back(argv[i]);
    if (files.empty()) return usage();
    if (json) std::puts("[");
    for (std::size_t i = 0; i < files.size(); ++i) {
        const auto r = run(files[i]);
        const auto& g = r.a.grid;
        if (json) {
            std::printf("  {\"file\":\"%s\",\"seconds\":%.3f,\"bpm\":%.4f,\"first_beat\":%.4f,\"downbeat\":%d,"
                        "\"confidence\":%.3f,\"first_sounding_beat\":%ld,\"ms\":%.1f}%s\n",
                        base(files[i]).c_str(), r.seconds, g.bpm, g.first_beat_s, g.downbeat, g.confidence,
                        g.first_sounding_beat, r.elapsed_ms, i + 1 < files.size() ? "," : "");
        } else {
            std::printf("%-40s %7.2f s  %9.4f BPM  primer tiempo %.3f s  compás en %d  conf %.2f  (%.0f ms)\n",
                        base(files[i]).c_str(), r.seconds, g.bpm, g.first_beat_s, g.downbeat, g.confidence, r.elapsed_ms);
            std::printf("    candidatos:");
            for (std::size_t c = 0; c < r.a.candidates.size() && c < 4; ++c)
                std::printf(" %.2f (%.3f)", r.a.candidates[c].bpm, r.a.candidates[c].weighted);
            std::puts("");
        }
    }
    if (json) std::puts("]");
    return 0;
}

int cmd_mxm(const char* path) {
    const Mxm m = read_mxm(path);
    std::printf("%s\n  bloques:", base(path).c_str());
    for (auto& c : m.chunks) std::printf(" %s", c.c_str());
    std::printf("\n  info: v%u, %u Hz, %.3f s\n", m.format_version, m.info_rate, m.duration_s());
    if (!m.prof) return 0;
    const auto& p = *m.prof;
    std::printf("  prof: v%u, %u Hz, %.4f BPM, confianza %.3f, contador %d B, %u bit/s\n", p.version, p.sample_rate,
                p.bpm, p.confidence, p.counter_width, p.bitrate);
    std::printf("  región analizada %.3f .. %.3f s\n", p.seconds(p.region_begin), p.seconds(p.region_end));
    const char* names[] = {"entrada", "salida", "reloj", "puntos"};
    for (std::size_t a = 0; a < p.arrays.size(); ++a) {
        std::printf("  %-8s (%zu):", names[a], p.arrays[a].size());
        for (std::size_t i = 0; i < p.arrays[a].size() && i < 12; ++i) std::printf(" %.3f", p.seconds(p.arrays[a][i]));
        std::puts("");
    }
    return 0;
}

int cmd_compare(const char* audio, const char* mxm, bool tsv) {
    const auto r = run(audio);
    const Mxm m = read_mxm(mxm);
    if (!m.prof) {
        std::fprintf(stderr, "%s: sin bloque prof\n", mxm);
        return 1;
    }
    const auto& p = *m.prof;
    const auto& g = r.a.grid;
    const double ratio = g.bpm / p.bpm;
    const bool same_level = std::abs(ratio - 1) < 0.02;
    double entry_off = NAN;
    long entry_k = 0;
    int entry_bar = -1;
    if (!p.arrays.empty() && p.arrays[0].size() >= 1) {
        // Las posiciones del perfil van en su propia base (prof.sample_rate).
        std::tie(entry_off, entry_k) = beat_offset(g, p.seconds(p.arrays[0][0]));
        entry_bar = static_cast<int>(((entry_k - g.downbeat) % 4 + 4) % 4);
    }
    if (tsv) {
        std::printf("%s\t%.3f\t%.4f\t%.4f\t%.5f\t%d\t%.4f\t%d\t%.3f\t%.3f\t%.0f\n", base(audio).c_str(), r.seconds, p.bpm,
                    g.bpm, ratio, same_level ? 1 : 0, entry_off, entry_bar, g.confidence, p.confidence, r.elapsed_ms);
        return 0;
    }
    std::printf("%s\n", base(audio).c_str());
    std::printf("  MixMeister %9.4f BPM (conf %.3f)\n  nuevo      %9.4f BPM (conf %.3f)   razón %.5f  %s\n", p.bpm,
                p.confidence, g.bpm, g.confidence, ratio, same_level ? "mismo nivel métrico" : "NIVEL DISTINTO");
    if (same_level) std::printf("  diferencia %.4f BPM (%.4f %%)\n", g.bpm - p.bpm, 100 * (ratio - 1));
    if (!std::isnan(entry_off))
        std::printf("  entrada de mezcla de MixMeister: a %+.3f tiempos de nuestra rejilla, tiempo %d del compás\n",
                    entry_off, entry_bar + 1);
    return 0;
}


/// Diagnóstico de fase: para la rejilla con la fase de MixMeister (0) y desplazada medio
/// tiempo (1), media por banda del ataque (flujo) y de la caída (nivel a +30 ms menos nivel
/// a +150 ms). Una línea por fase: nombre, fase, nuestra_fase_coincide, 48 flujos, 48 caídas.
int cmd_phasediag(const char* audio, const char* mxm) {
    const Buffer b = read_audio(audio);
    const auto mono = to_mono(b);
    const RhythmAnalysis a = analyze_rhythm(mono, b.sample_rate);
    const Mxm m = read_mxm(mxm);
    if (!m.prof || m.prof->arrays.empty() || m.prof->arrays[0].empty()) return 1;
    const auto& g = a.grid;
    if (std::abs(g.bpm / m.prof->bpm - 1) > 0.02) return 1;  // solo mismo nivel
    const auto& e = a.env;
    const std::size_t nb = e.n_bands, frames = e.bands.size() / nb;
    const double P = g.period();
    const double t_mm = m.prof->seconds(m.prof->arrays[0][0]);
    const double ours = std::abs(beat_offset(g, t_mm).first) < 0.25 ? 1 : 0;
    auto at = [&](double t, std::size_t band, bool flux) {
        const double x = (t - e.frame_offset_s) / e.hop_s;
        const auto i = static_cast<long>(std::floor(x));
        if (i < 1 || i + 1 >= static_cast<long>(frames)) return 0.0;
        auto B = [&](long f) { return static_cast<double>(e.bands[static_cast<std::size_t>(f) * nb + band]); };
        if (flux) {  // máximo del flujo positivo en ±1 frame
            double best = 0;
            for (long f = i - 1; f <= i + 2 && f + 1 < static_cast<long>(frames); ++f) best = std::max(best, B(f) - B(f - 1));
            return best;
        }
        const long f30 = std::lround((t + 0.030) / e.hop_s), f150 = std::lround((t + 0.150) / e.hop_s);
        if (f150 >= static_cast<long>(frames)) return 0.0;
        return B(f30) - B(f150);
    };
    for (int ph = 0; ph < 2; ++ph) {
        std::vector<double> fl(nb, 0), dc(nb, 0);
        long n = 0;
        double t0 = std::fmod(t_mm + ph * P / 2, P);
        for (double t = t0; t + 0.2 < e.duration(); t += P, ++n)
            for (std::size_t k = 0; k < nb; ++k) fl[k] += at(t, k, true), dc[k] += at(t, k, false);
        std::printf("%s\t%d\t%.0f", base(audio).c_str(), ph, ours);
        for (auto v : fl) std::printf("\t%.4f", n ? v / n : 0);
        for (auto v : dc) std::printf("\t%.4f", n ? v / n : 0);
        std::puts("");
    }
    return 0;
}


/// Diagnóstico de compás: posición (0-3) de la entrada de MixMeister en nuestra rejilla y,
/// por posición, los rasgos de compás. Solo pistas al mismo nivel y en fase (< 0,1 tiempos).
int cmd_bardiag(const char* audio, const char* mxm) {
    const Buffer b = read_audio(audio);
    const auto mono = to_mono(b);
    const RhythmAnalysis a = analyze_rhythm(mono, b.sample_rate);
    const Mxm m = read_mxm(mxm);
    if (!m.prof || m.prof->arrays.empty() || m.prof->arrays[0].empty()) return 1;
    const auto& g = a.grid;
    if (std::abs(g.bpm / m.prof->bpm - 1) > 0.02) return 1;
    const auto [off, k] = beat_offset(g, m.prof->seconds(m.prof->arrays[0][0]));
    if (std::abs(off) >= 0.1) return 1;
    const auto f = bar_features(a.env, g.first_beat_s, g.period(), g.first_sounding_beat);
    std::printf("%s\t%ld", base(audio).c_str(), ((k % 4) + 4) % 4);
    for (int j = 0; j < 4; ++j)
        for (double v : f[j]) std::printf("\t%.5f", v);
    std::puts("");
    return 0;
}


/// Diagnóstico de nivel: candidatos de la familia del mejor tempo, cuál coincide con el BPM de
/// MixMeister (±2 %) y sus rasgos. Línea: nombre, bpm_mm, n, y n × (bpm, etiqueta, rasgos).
int cmd_leveldiag(const char* audio, const char* mxm) {
    const Buffer b = read_audio(audio);
    const auto mono = to_mono(b);
    const auto env = onset_envelope(mono, b.sample_rate);
    const auto cands = tempo_candidates(env);
    const Mxm m = read_mxm(mxm);
    if (!m.prof || cands.empty()) return 1;
    const auto lv = level_candidates(env, cands);
    std::printf("%s\t%.4f\t%zu", base(audio).c_str(), m.prof->bpm, lv.size());
    for (const auto& c : lv) {
        std::printf("\t%.4f\t%d", c.bpm, std::abs(c.bpm / m.prof->bpm - 1) < 0.02 ? 1 : 0);
        for (double v : c.f) std::printf("\t%.5f", v);
    }
    std::puts("");
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) return usage();
    try {
        const std::string c = argv[1];
        if (c == "analyze") return cmd_analyze(argc, argv);
        if (c == "mxm" && argc == 3) return cmd_mxm(argv[2]);
        if (c == "compare" && argc == 4) return cmd_compare(argv[2], argv[3], false);
        if (c == "tsv" && argc == 4) return cmd_compare(argv[2], argv[3], true);
        if (c == "phasediag" && argc == 4) return cmd_phasediag(argv[2], argv[3]);
        if (c == "bardiag" && argc == 4) return cmd_bardiag(argv[2], argv[3]);
        if (c == "leveldiag" && argc == 4) return cmd_leveldiag(argv[2], argv[3]);
        return usage();
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
}
