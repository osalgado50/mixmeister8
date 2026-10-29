// mmn — línea de comandos del motor MMStudio Next.
#include "mmn/analysis.hpp"
#include "mmn/audio.hpp"
#include "mmn/key.hpp"
#include "mmn/mix.hpp"
#include "mmn/mmp.hpp"

#include <fstream>
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
        "mmn key [--chroma] fichero...       tonalidad y Camelot (con --chroma, el cromagrama)\n"
        "mmn transicion a b salida.wav       mezcla A → B, cuadrada a tiempo y a compás\n"
        "mmn sesion lista.mmp salida.wav [carpeta...]   renderiza una sesión de MixMeister (+ .cue)\n"
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
double interp_at(const std::vector<float>& v, double x) {
    if (v.empty() || x < 0) return 0;
    const auto i = static_cast<std::size_t>(x);
    if (i + 1 >= v.size()) return 0;
    const double f = x - static_cast<double>(i);
    return v[i] + f * (v[i + 1] - v[i]);
}

int cmd_phasediag(const char* audio, const char* mxm, bool quarters = false) {
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
    // phasediag: fase de MixMeister (0) y contratiempo (1). phasediag4: las cuatro posiciones a un
    // cuarto de tiempo (0 = MixMeister); en vez de «ours» global, si nuestra rejilla cae en esa
    // posición (±⅛ de tiempo), y además el pulso de bombo (√graves·banda) que usa la búsqueda.
    const int nph = quarters ? 4 : 2;
    for (int ph = 0; ph < nph; ++ph) {
        std::vector<double> fl(nb, 0), dc(nb, 0);
        long n = 0;
        const double t0 = std::fmod(t_mm + ph * P / nph, P);
        double kick = 0;
        for (double t = t0; t + 0.2 < e.duration(); t += P, ++n) {
            for (std::size_t k = 0; k < nb; ++k) fl[k] += at(t, k, true), dc[k] += at(t, k, false);
            const double lo = interp_at(e.low, (t - e.low_offset_s) / e.hop_s), fu = interp_at(e.full, (t - e.offset_s) / e.hop_s);
            kick += std::sqrt(std::max(0.0, lo * fu));
        }
        const double mine = quarters ? (std::abs(beat_offset(g, t0).first) < 0.125 ? 1 : 0) : ours;
        std::printf("%s\t%d\t%.0f", base(audio).c_str(), ph, mine);
        if (quarters) std::printf("\t%.5f", n ? kick / n : 0);
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


int cmd_key(int argc, char** argv) {
    bool chroma = false;
    for (int i = 2; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--chroma")) { chroma = true; continue; }
        try {
            const Buffer b = read_audio(argv[i]);
            const Chroma c = chromagram(to_mono(b), b.sample_rate);
            const Key k = estimate_key(c);
            std::printf("%s\t%s\t%s\t%.3f", base(argv[i]).c_str(), k.name().c_str(), k.camelot().c_str(), k.margin);
            if (chroma)
                for (double v : c) std::printf("\t%.5f", v);
            std::puts("");
        } catch (const std::exception& e) {
            std::fprintf(stderr, "%s: %s\n", argv[i], e.what());
        }
    }
    return 0;
}


/// Diagnóstico de ventanas de mezcla: las 4 marcas de MixMeister (entrada inicio/fin, salida
/// inicio/fin) en tiempos de nuestra rejilla, más nuestro primer/último tiempo con sonido,
/// compás y número de tiempos. Solo pistas al mismo nivel.
int cmd_mixdiag(const char* audio, const char* mxm) {
    const Buffer b = read_audio(audio);
    const RhythmAnalysis a = analyze_rhythm(to_mono(b), b.sample_rate);
    const Mxm m = read_mxm(mxm);
    if (!m.prof || m.prof->arrays.size() < 2 || m.prof->arrays[0].size() < 2 || m.prof->arrays[1].size() < 2) return 1;
    const auto& g = a.grid;
    if (std::abs(g.bpm / m.prof->bpm - 1) > 0.02) return 1;
    auto bt = [&](std::uint64_t s) { return (m.prof->seconds(s) - g.first_beat_s) / g.period(); };
    const long nbeats = static_cast<long>((a.env.duration() - g.first_beat_s) / g.period());
    std::printf("%s\t%.3f\t%.3f\t%.3f\t%.3f\t%ld\t%ld\t%d\t%ld\t%.3f\n", base(audio).c_str(), bt(m.prof->arrays[0][0]),
                bt(m.prof->arrays[0][1]), bt(m.prof->arrays[1][0]), bt(m.prof->arrays[1][1]), g.first_sounding_beat,
                g.last_sounding_beat, g.downbeat, nbeats, b.seconds());
    return 0;
}


int cmd_transicion(const char* fa, const char* fb, const char* out) {
    const Track a = load_track(fa), b = load_track(fb);
    TransitionInfo info;
    const Buffer mix = render_transition(a, b, &info);
    write_wav16(out, mix);
    std::printf("%s (%.2f BPM) → %s (%.2f BPM)\n", base(fa).c_str(), a.grid.bpm, base(fb).c_str(), b.grid.bpm);
    std::printf("  solape de %d tiempos: %.2f s → %.2f s (%.2f s)\n", a.windows.phrase, info.start_s,
                info.start_s + info.length_s, info.length_s);
    std::printf("  mezcla: %.2f s → %s\n", info.total_s, out);
    return 0;
}


int cmd_sesion(int argc, char** argv) {
    const std::string list = argv[2], out = argv[3];
    std::vector<std::string> dirs;
    for (int i = 4; i < argc; ++i) dirs.emplace_back(argv[i]);
    const auto items = read_mmp(list);
    std::vector<Track> tracks;
    std::vector<std::string> names;
    for (const auto& it : items) {
        const std::string p = resolve_track(it.path, dirs);
        if (p.empty()) {
            std::fprintf(stderr, "no encuentro: %s (se salta)\n", it.path.c_str());
            continue;
        }
        tracks.push_back(load_track(p));
        names.push_back(base(p));
        std::printf("  %2zu. %-40s %7.2f BPM  entrada t%ld  salida t%ld\n", tracks.size(), names.back().c_str(),
                    tracks.back().grid.bpm, tracks.back().windows.entry_beat, tracks.back().windows.exit_beat);
    }
    if (tracks.empty()) {
        std::fprintf(stderr, "ninguna pista encontrada\n");
        return 1;
    }
    SessionInfo info;
    const Buffer mix = render_session(tracks, &info);
    write_wav16(out, mix);
    // Hoja CUE con el inicio de cada pista (minutos:segundos:fotogramas de 1/75 s).
    std::string cue = out.substr(0, out.find_last_of('.')) + ".cue";
    std::ofstream c(cue);
    c << "FILE \"" << base(out) << "\" WAVE\n";
    for (std::size_t i = 0; i < tracks.size(); ++i) {
        const auto frames = static_cast<long>(std::llround(info.starts[i] * 75));
        char ts[32];
        std::snprintf(ts, sizeof ts, "%02ld:%02ld:%02ld", frames / 75 / 60, (frames / 75) % 60, frames % 75);
        c << "  TRACK " << (i < 9 ? "0" : "") << i + 1 << " AUDIO\n    TITLE \"" << names[i] << "\"\n    INDEX 01 " << ts << "\n";
    }
    std::printf("sesión: %zu pistas, %.1f s → %s (+ %s)\n", tracks.size(), info.total_s, out.c_str(), base(cue).c_str());
    return 0;
}

/// Lee cada lista, la vuelve a escribir desde el modelo y compara byte a byte.
int cmd_mmp_check(int argc, char** argv) {
    int ok = 0, bad = 0;
    for (int i = 2; i < argc; ++i) {
        try {
            const auto in = read_file(argv[i]);
            const auto out = serialize_playlist(parse_playlist(in));
            if (in == out) { ++ok; continue; }
            std::size_t at = 0;
            while (at < in.size() && at < out.size() && in[at] == out[at]) ++at;
            std::printf("DIFIERE\t%s\tbyte %zu (leído %zu, escrito %zu)\n", argv[i], at, in.size(), out.size());
            ++bad;
        } catch (const std::exception& e) {
            std::printf("ERROR\t%s\t%s\n", argv[i], e.what());
            ++bad;
        }
    }
    std::printf("idénticas %d de %d\n", ok, ok + bad);
    return bad ? 1 : 0;
}

int cmd_mmp_dump(const char* path) {
    const Playlist p = read_playlist(path);
    std::printf("versión %08x %08x · master %.2f dB · %zu efectos de master\n", p.version[0], p.version[1],
                static_cast<double>(p.master_gain_db), p.master_effects.size());
    for (const auto& e : p.master_effects) std::printf("  efecto master «%s» [%s] %zu parámetros\n", e.name.c_str(), e.plugin_code().c_str(), e.params.size());
    int n = 0;
    for (const auto& t : p.tracks) {
        std::printf("%2d. %s%s\n", ++n, t.path.c_str(), t.overlay ? "  [overlay]" : "");
        std::printf("    %.3f BPM (original %.3f), tono %+.2f, transición %s → %s, %zu compases\n", t.bpm, t.original_bpm(),
                    static_cast<double>(t.key_semitones), t.has_transition_in ? t.transition_in.c_str() : "—",
                    t.has_transition_out ? t.transition_out.c_str() : "—", t.beat_markers.size());
        for (const auto& e : t.effects) std::printf("    efecto «%s» [%s] %zu parámetros\n", e.name.c_str(), e.plugin_code().c_str(), e.params.size());
        for (const auto& it : t.layer) {
            if (it.is_segment) {
                const auto& s = it.segment;
                std::printf("    segmento %9.3f → %9.3f s%s", s.src_start_us / 1e6, s.src_end_us / 1e6, s.reversed ? " al revés" : "");
                if (s.kind == 2) std::printf("  overlay en compás %d + %.3f", s.overlay_measure, static_cast<double>(s.overlay_fraction));
                std::printf("\n");
            } else if (it.marker.type != kMeasure) {
                const auto& m = it.marker;
                std::printf("    %9.3f s  %-22s %g%s%s\n", m.pos_us / 1e6, marker_name(m.type), static_cast<double>(m.value),
                            m.label.empty() ? "" : "  «", m.label.empty() ? "" : (m.label + "»").c_str());
            }
        }
    }
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) return usage();
    try {
        const std::string c = argv[1];
        if (c == "analyze") return cmd_analyze(argc, argv);
        if (c == "key") return cmd_key(argc, argv);
        if (c == "transicion" && argc == 5) return cmd_transicion(argv[2], argv[3], argv[4]);
        if (c == "sesion" && argc >= 4) return cmd_sesion(argc, argv);
        if (c == "mxm" && argc == 3) return cmd_mxm(argv[2]);
        if (c == "compare" && argc == 4) return cmd_compare(argv[2], argv[3], false);
        if (c == "tsv" && argc == 4) return cmd_compare(argv[2], argv[3], true);
        if (c == "phasediag" && argc == 4) return cmd_phasediag(argv[2], argv[3]);
        if (c == "phasediag4" && argc == 4) return cmd_phasediag(argv[2], argv[3], true);
        if (c == "bardiag" && argc == 4) return cmd_bardiag(argv[2], argv[3]);
        if (c == "leveldiag" && argc == 4) return cmd_leveldiag(argv[2], argv[3]);
        if (c == "mixdiag" && argc == 4) return cmd_mixdiag(argv[2], argv[3]);
        if (c == "mmp-check" && argc >= 3) return cmd_mmp_check(argc, argv);
        if (c == "mmp-dump" && argc == 3) return cmd_mmp_dump(argv[2]);
        return usage();
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
}
