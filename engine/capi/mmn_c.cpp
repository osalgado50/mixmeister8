// mmn_c.cpp — implementación de la API en C (mmn_c.h) sobre el motor C++.
#include "mmn_c.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>

#include "../src/util/json.hpp"
#include "mmn/analysis.hpp"
#include "mmn/audio.hpp"
#include "mmn/key.hpp"
#include "mmn/mmp.hpp"

using namespace mmn;
namespace J = mmn::json;

struct mmn_playlist {
    Playlist pl;
    std::string json;  // último JSON devuelto
};

namespace {

char* dup(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (p) std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}
void set_err(char** err, const std::string& m) {
    if (err) *err = dup(m);
}

std::string hex16(const std::array<std::uint8_t, 16>& b) {
    static const char* h = "0123456789ABCDEF";
    std::string s;
    for (auto x : b) s += h[x >> 4], s += h[x & 15];
    return s;
}
std::array<std::uint8_t, 16> unhex16(const std::string& s) {
    std::array<std::uint8_t, 16> b{};
    std::string t;
    for (char c : s) if (std::isxdigit(static_cast<unsigned char>(c))) t += c;
    for (std::size_t i = 0; i < 16 && 2 * i + 1 < t.size(); ++i) b[i] = static_cast<std::uint8_t>(std::stoul(t.substr(2 * i, 2), nullptr, 16));
    return b;
}

J::Value effect_json(const Effect& e) {
    J::Array params;
    for (float v : e.params) params.emplace_back(static_cast<double>(v));
    return J::Object{{"plugin_id", e.plugin_id}, {"code", e.plugin_code()}, {"slot", e.slot}, {"flags", e.flags},
                     {"params", params}, {"name", e.name}};
}
Effect effect_from(const J::Value& v, const Effect* base) {
    Effect e = base ? *base : Effect{};
    e.plugin_id = static_cast<std::uint32_t>(v["plugin_id"].num(e.plugin_id));
    e.slot = static_cast<std::uint32_t>(v["slot"].num(e.slot));
    e.flags = static_cast<std::uint32_t>(v["flags"].num(e.flags));
    e.name = v["name"].str(e.name);
    if (v.has("params")) {
        e.params.clear();
        for (const auto& x : v["params"].arr()) e.params.push_back(static_cast<float>(x.num()));
    }
    return e;
}

J::Value playlist_json(const Playlist& p) {
    J::Array tracks;
    int ti = 0;
    for (const auto& t : p.tracks) {
        J::Array layer;
        int li = 0;
        for (const auto& it : t.layer) {
            if (it.is_segment) {
                const auto& s = it.segment;
                layer.emplace_back(J::Object{{"_src", li}, {"kind", "segment"}, {"reversed", s.reversed}, {"class", s.kind},
                                             {"src_start_us", s.src_start_us}, {"src_end_us", s.src_end_us}, {"anchor_us", s.anchor_us},
                                             {"overlay_measure", s.overlay_measure}, {"overlay_fraction", static_cast<double>(s.overlay_fraction)},
                                             {"overlay_rate", s.overlay_rate}});
            } else {
                const auto& m = it.marker;
                layer.emplace_back(J::Object{{"_src", li}, {"kind", "marker"}, {"type", m.type}, {"name", marker_name(m.type)},
                                             {"pos_us", m.pos_us}, {"flag", m.flag}, {"value", static_cast<double>(m.value)}, {"label", m.label}});
            }
            ++li;
        }
        J::Array beats;
        for (const auto& m : t.beat_markers) beats.emplace_back(m.pos_us);
        J::Array fx;
        for (const auto& e : t.effects) fx.push_back(effect_json(e));
        std::int64_t len = 0;
        for (const auto& s : t.source_segments) len = std::max(len, s.src_end_us);
        tracks.emplace_back(J::Object{
            {"_src", ti++},
            {"path", t.path},
            {"transition_in", t.has_transition_in ? J::Value(t.transition_in) : J::Value(nullptr)},
            {"transition_out", t.has_transition_out ? J::Value(t.transition_out) : J::Value(nullptr)},
            {"file_id", hex16(t.file_id)},
            {"bpm", t.bpm},
            {"original_bpm", t.original_bpm()},
            {"bar_us", t.bar_us},
            {"length_us", len},
            {"overlay", t.overlay},
            {"key_semitones", static_cast<double>(t.key_semitones)},
            {"beat_markers_us", beats},
            {"effects", fx},
            {"layer", layer}});
    }
    J::Array mfx;
    for (const auto& e : p.master_effects) mfx.push_back(effect_json(e));
    return J::Object{{"format", "mmp"}, {"version", J::Array{p.version[0], p.version[1]}},
                     {"master_gain_db", static_cast<double>(p.master_gain_db)}, {"master_effects", mfx}, {"tracks", tracks}};
}

Playlist playlist_from(const J::Value& v, const Playlist& old) {
    Playlist p;
    p.source = old.source;
    p.version = old.version;
    p.master_gain_db = static_cast<float>(v["master_gain_db"].num(old.master_gain_db));
    {
        const auto& a = v["master_effects"].arr();
        for (std::size_t i = 0; i < a.size(); ++i) p.master_effects.push_back(effect_from(a[i], i < old.master_effects.size() ? &old.master_effects[i] : nullptr));
    }
    for (const auto& tv : v["tracks"].arr()) {
        const int src = static_cast<int>(tv["_src"].num(-1));
        const PlaylistTrack* base = (src >= 0 && static_cast<std::size_t>(src) < old.tracks.size()) ? &old.tracks[static_cast<std::size_t>(src)] : nullptr;
        PlaylistTrack t = base ? *base : PlaylistTrack{};
        t.path = tv["path"].str(t.path);
        if (tv.has("transition_in")) t.has_transition_in = !tv["transition_in"].is_null(), t.transition_in = tv["transition_in"].str();
        if (tv.has("transition_out")) t.has_transition_out = !tv["transition_out"].is_null(), t.transition_out = tv["transition_out"].str();
        if (tv.has("file_id")) t.file_id = unhex16(tv["file_id"].str());
        t.bpm = tv["bpm"].num(t.bpm);
        t.bar_us = static_cast<std::int64_t>(tv["bar_us"].num(static_cast<double>(t.bar_us)));
        t.overlay = tv["overlay"].boolean(t.overlay);
        t.key_semitones = static_cast<float>(tv["key_semitones"].num(t.key_semitones));
        if (tv.has("beat_markers_us")) {
            const auto& a = tv["beat_markers_us"].arr();
            std::vector<Marker> bm;
            for (std::size_t i = 0; i < a.size(); ++i) {
                Marker m = base && i < base->beat_markers.size() ? base->beat_markers[i] : Marker{};
                m.type = kMeasure;
                m.pos_us = static_cast<std::int64_t>(a[i].num());
                bm.push_back(m);
            }
            t.beat_markers = std::move(bm);
        }
        if (tv.has("effects")) {
            const auto& a = tv["effects"].arr();
            t.effects.clear();
            for (std::size_t i = 0; i < a.size(); ++i) t.effects.push_back(effect_from(a[i], base && i < base->effects.size() ? &base->effects[i] : nullptr));
        }
        if (tv.has("layer")) {
            std::vector<PlaylistTrack::LayerItem> layer;
            for (const auto& iv : tv["layer"].arr()) {
                const int ls = static_cast<int>(iv["_src"].num(-1));
                const PlaylistTrack::LayerItem* ob = (base && ls >= 0 && static_cast<std::size_t>(ls) < base->layer.size()) ? &base->layer[static_cast<std::size_t>(ls)] : nullptr;
                PlaylistTrack::LayerItem it = ob ? *ob : PlaylistTrack::LayerItem{};
                if (iv["kind"].str() == "segment") {
                    if (!ob || !ob->is_segment) it = {true, {}, {}};
                    auto& s = it.segment;
                    s.reversed = iv["reversed"].boolean(s.reversed);
                    s.kind = static_cast<std::uint32_t>(iv["class"].num(s.kind));
                    s.src_start_us = static_cast<std::int64_t>(iv["src_start_us"].num(static_cast<double>(s.src_start_us)));
                    s.src_end_us = static_cast<std::int64_t>(iv["src_end_us"].num(static_cast<double>(s.src_end_us)));
                    s.anchor_us = static_cast<std::int64_t>(iv["anchor_us"].num(static_cast<double>(s.anchor_us)));
                    s.overlay_measure = static_cast<std::int32_t>(iv["overlay_measure"].num(s.overlay_measure));
                    s.overlay_fraction = static_cast<float>(iv["overlay_fraction"].num(s.overlay_fraction));
                    s.overlay_rate = iv["overlay_rate"].num(s.overlay_rate);
                } else {
                    if (!ob || ob->is_segment) it = {false, {}, {}};
                    auto& m = it.marker;
                    m.type = static_cast<std::uint32_t>(iv["type"].num(m.type));
                    m.pos_us = static_cast<std::int64_t>(iv["pos_us"].num(static_cast<double>(m.pos_us)));
                    m.flag = static_cast<std::uint32_t>(iv["flag"].num(m.flag));
                    m.value = static_cast<float>(iv["value"].num(m.value));
                    m.label = iv["label"].str(m.label);
                }
                layer.push_back(std::move(it));
            }
            t.layer = std::move(layer);
        }
        if (!base && t.source_segments.empty()) {
            // Pista nueva: la pista entera como segmento de origen (así lo escribe MixMeister).
            Segment whole;
            whole.src_end_us = static_cast<std::int64_t>(tv["length_us"].num(0));
            t.source_segments.push_back(whole);
            t.tempo_order.assign(t.beat_markers.size(), false);
            t.tempo_order.push_back(true);
        }
        p.tracks.push_back(std::move(t));
    }
    return p;
}

}  // namespace

extern "C" {

void mmn_free_string(char* s) { std::free(s); }
const char* mmn_version(void) { return "8.0.0"; }

mmn_playlist* mmn_playlist_new(void) { return new mmn_playlist(); }

mmn_playlist* mmn_playlist_open(const char* path, char** err) {
    try {
        auto* p = new mmn_playlist();
        p->pl = read_playlist(path);
        return p;
    } catch (const std::exception& e) {
        set_err(err, e.what());
        return nullptr;
    }
}

void mmn_playlist_free(mmn_playlist* p) { delete p; }

const char* mmn_playlist_json(mmn_playlist* p) {
    p->json = J::dump(playlist_json(p->pl));
    return p->json.c_str();
}

int mmn_playlist_set_json(mmn_playlist* p, const char* json, char** err) {
    try {
        p->pl = playlist_from(J::parse(json), p->pl);
        return 0;
    } catch (const std::exception& e) {
        set_err(err, e.what());
        return -1;
    }
}

int mmn_playlist_save(mmn_playlist* p, const char* path, char** err) {
    try {
        write_playlist(path, p->pl);
        p->pl = read_playlist(path);  // lo guardado pasa a ser la referencia de lo no interpretado
        return 0;
    } catch (const std::exception& e) {
        set_err(err, e.what());
        return -1;
    }
}

double mmn_audio_peaks(const char* path, float* out, size_t bins, char** err) {
    try {
        const Buffer b = read_audio(path);
        const auto n = b.frames();
        std::fill(out, out + bins, 0.0f);
        if (n == 0 || bins == 0) return 0;
        for (const auto& ch : b.ch)
            for (std::size_t i = 0; i < n; ++i) {
                const std::size_t k = std::min(bins - 1, i * bins / n);
                out[k] = std::max(out[k], std::fabs(ch[i]));
            }
        return b.seconds();
    } catch (const std::exception& e) {
        set_err(err, e.what());
        return -1;
    }
}

double mmn_audio_peaks3(const char* path, float* out, size_t bins, char** err) {
    try {
        const Buffer b = read_audio(path);
        const auto n = b.frames();
        std::fill(out, out + bins * 4, 0.0f);
        if (n == 0 || bins == 0) return 0;
        // Bandas con filtros de un polo (graves < 200 Hz, agudos > 2 kHz, medios entre ambos).
        const double sr = b.sample_rate;
        const double al = 1 - std::exp(-2 * 3.14159265358979 * 200 / sr), ah = 1 - std::exp(-2 * 3.14159265358979 * 2000 / sr);
        double lp200 = 0, lp2k = 0;
        const std::size_t nc = b.ch.size();
        for (std::size_t i = 0; i < n; ++i) {
            double x = 0;
            for (const auto& ch : b.ch) x += ch[i];
            x /= static_cast<double>(nc);
            lp200 += (x - lp200) * al;
            lp2k += (x - lp2k) * ah;
            const double lo = lp200, mid = lp2k - lp200, hi = x - lp2k;
            float* o = out + 4 * std::min(bins - 1, i * bins / n);
            o[0] = std::max(o[0], static_cast<float>(std::fabs(x)));
            o[1] = std::max(o[1], static_cast<float>(std::fabs(lo)));
            o[2] = std::max(o[2], static_cast<float>(std::fabs(mid)));
            o[3] = std::max(o[3], static_cast<float>(std::fabs(hi)));
        }
        return b.seconds();
    } catch (const std::exception& e) {
        set_err(err, e.what());
        return -1;
    }
}

char* mmn_analyze_json(const char* path, char** err) {
    try {
        const Buffer b = read_audio(path);
        const auto mono = to_mono(b);
        const auto r = analyze_rhythm(mono, b.sample_rate);
        const auto k = estimate_key(chromagram(mono, b.sample_rate));
        const auto w = mix_windows(r.grid);
        const J::Value v = J::Object{{"bpm", r.grid.bpm}, {"first_beat_s", r.grid.first_beat_s}, {"downbeat", r.grid.downbeat},
                                     {"first_sounding_beat", static_cast<double>(r.grid.first_sounding_beat)},
                                     {"confidence", r.grid.confidence},
                                     {"entry_beat", static_cast<double>(w.entry_beat)}, {"exit_beat", static_cast<double>(w.exit_beat)}, {"seconds", b.seconds()}, {"sample_rate", b.sample_rate},
                                     {"key", k.name()}, {"camelot", k.camelot()}, {"key_tonic", k.tonic}, {"key_minor", k.minor}};
        return dup(J::dump(v));
    } catch (const std::exception& e) {
        set_err(err, e.what());
        return nullptr;
    }
}

}  // extern "C"
