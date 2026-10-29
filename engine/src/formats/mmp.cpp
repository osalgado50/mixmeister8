#include "mmn/mmp.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>

namespace mmn {
namespace {

using Bytes = std::vector<std::uint8_t>;

template <class T>
T get(const Bytes& d, std::size_t p) {
    if (p + sizeof(T) > d.size()) throw std::out_of_range("mmp: lectura fuera del bloque");
    T v;
    std::memcpy(&v, d.data() + p, sizeof(T));
    return v;
}
template <class T>
void put(Bytes& d, std::size_t p, T v) {
    if (p + sizeof(T) > d.size()) d.resize(p + sizeof(T), 0);
    std::memcpy(d.data() + p, &v, sizeof(T));
}

std::uint32_t le32(const std::uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (std::uint32_t(p[3]) << 24); }

void parse_children(const Bytes& b, std::size_t p, std::size_t end, std::vector<RiffChunk>& out) {
    while (p + 8 <= end) {
        RiffChunk c;
        c.id.assign(reinterpret_cast<const char*>(&b[p]), 4);
        const std::size_t len = le32(&b[p + 4]), body = p + 8;
        if (body + len > end) throw std::runtime_error("mmp: bloque " + c.id + " sale del fichero");
        if (c.id == "LIST" || c.id == "RIFF") {
            if (len < 4) throw std::runtime_error("mmp: LIST sin tipo");
            c.type.assign(reinterpret_cast<const char*>(&b[body]), 4);
            parse_children(b, body + 4, body + len, c.children);
        } else {
            c.data.assign(b.begin() + static_cast<long>(body), b.begin() + static_cast<long>(body + len));
        }
        out.push_back(std::move(c));
        p = body + len + (len & 1);
    }
    if (p != end && p + 1 != end) throw std::runtime_error("mmp: restos sin bloque al final de una lista");
}

void emit(const RiffChunk& c, Bytes& out) {
    out.insert(out.end(), c.id.begin(), c.id.end());
    const std::size_t at = out.size();
    out.resize(at + 4);
    const std::size_t start = out.size();
    if (c.is_list()) {
        out.insert(out.end(), c.type.begin(), c.type.end());
        for (const auto& k : c.children) emit(k, out);
    } else {
        out.insert(out.end(), c.data.begin(), c.data.end());
    }
    const auto len = static_cast<std::uint32_t>(out.size() - start);
    std::memcpy(&out[at], &len, 4);
    if (len & 1) out.push_back(0);
}

RiffChunk leaf(const std::string& id, Bytes data) {
    RiffChunk c;
    c.id = id;
    c.data = std::move(data);
    return c;
}
RiffChunk list(const std::string& type) {
    RiffChunk c;
    c.id = "LIST";
    c.type = type;
    return c;
}

std::string lower(std::string s) {
    for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

}  // namespace

// ------------------------------------------------------------------- RIFF -----------------------

const RiffChunk* RiffChunk::find(const std::string& key) const {
    for (const auto& c : children)
        if ((c.is_list() ? c.type : c.id) == key) return &c;
    return nullptr;
}

RiffChunk parse_riff(const Bytes& b) {
    std::vector<RiffChunk> top;
    parse_children(b, 0, b.size(), top);
    if (top.size() != 1 || top[0].id != "RIFF") throw std::runtime_error("mmp: no es un fichero RIFF");
    return std::move(top[0]);
}

Bytes serialize_riff(const RiffChunk& root) {
    Bytes out;
    emit(root, out);
    return out;
}

Bytes read_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("no se puede abrir: " + path);
    return Bytes{std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}

void write_file(const std::string& path, const Bytes& bytes) {
    // Se escribe a un temporal y se renombra: un corte a mitad no deja la lista estropeada.
    const std::string tmp = path + ".mm8tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f) throw std::runtime_error("no se puede escribir: " + path);
        f.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        if (!f) throw std::runtime_error("error al escribir: " + path);
    }
    std::filesystem::rename(tmp, path);
}

std::string from_utf16(const Bytes& d, std::size_t p, std::size_t len) {
    const std::size_t end = len == SIZE_MAX ? d.size() : std::min(d.size(), p + len);
    std::string out;
    for (std::size_t i = p; i + 1 < end; i += 2) {
        std::uint32_t c = d[i] | (d[i + 1] << 8);
        if (c == 0) break;
        if (c >= 0xD800 && c < 0xDC00 && i + 3 < end) {
            const std::uint32_t lo = d[i + 2] | (d[i + 3] << 8);
            if (lo >= 0xDC00 && lo < 0xE000) c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00), i += 2;
        }
        if (c < 0x80) out += static_cast<char>(c);
        else if (c < 0x800) out += static_cast<char>(0xC0 | (c >> 6)), out += static_cast<char>(0x80 | (c & 0x3F));
        else if (c < 0x10000)
            out += static_cast<char>(0xE0 | (c >> 12)), out += static_cast<char>(0x80 | ((c >> 6) & 0x3F)),
                out += static_cast<char>(0x80 | (c & 0x3F));
        else
            out += static_cast<char>(0xF0 | (c >> 18)), out += static_cast<char>(0x80 | ((c >> 12) & 0x3F)),
                out += static_cast<char>(0x80 | ((c >> 6) & 0x3F)), out += static_cast<char>(0x80 | (c & 0x3F));
    }
    return out;
}

Bytes to_utf16(const std::string& s) {
    Bytes out;
    auto unit = [&](std::uint32_t u) { out.push_back(static_cast<std::uint8_t>(u & 0xFF)), out.push_back(static_cast<std::uint8_t>(u >> 8)); };
    for (std::size_t i = 0; i < s.size();) {
        const auto c0 = static_cast<unsigned char>(s[i]);
        std::uint32_t cp;
        int n;
        if (c0 < 0x80) cp = c0, n = 1;
        else if ((c0 >> 5) == 6) cp = c0 & 0x1F, n = 2;
        else if ((c0 >> 4) == 14) cp = c0 & 0x0F, n = 3;
        else cp = c0 & 0x07, n = 4;
        for (int k = 1; k < n && i + static_cast<std::size_t>(k) < s.size(); ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + static_cast<std::size_t>(k)]) & 0x3F);
        i += static_cast<std::size_t>(n);
        if (cp >= 0x10000) cp -= 0x10000, unit(0xD800 + (cp >> 10)), unit(0xDC00 + (cp & 0x3FF));
        else unit(cp);
    }
    unit(0);
    return out;
}

// ------------------------------------------------------------------- piezas ---------------------

const char* marker_name(std::uint32_t t) {
    switch (t) {
        case kIntroAnchor: return "ancla de entrada";
        case kOutroAnchor: return "ancla de salida";
        case kAutoVolumeIn: return "volumen automático (entrada)";
        case kAutoVolume: return "volumen automático";
        case kVolume: return "volumen";
        case kTreble: return "agudos";
        case kMidrange: return "medios";
        case kBass: return "graves";
        case kTempo: return "tempo";
        case kOriginalTempo: return "tempo original";
        case kLabel: return "etiqueta";
        case kEffectParam: return "parámetro de efecto";
        case kMeasure: return "compás";
        case kLoopStart: return "inicio de bucle";
        case kLoopEnd: return "fin de bucle";
        default: return "desconocido";
    }
}

// TRKM: +0 u16 tamaño (0x20) · +2 u16 versión (1) · +4 u32 tipo · +8 i64 posición µs ·
//       +16 u32 indicador · +20 f32 valor · etiquetas: +24 u32 caracteres con el cero, +32 UTF-16.
Marker Marker::decode(const Bytes& d) {
    Marker m;
    m.raw = d;
    m.type = get<std::uint32_t>(d, 4);
    m.pos_us = get<std::int64_t>(d, 8);
    m.flag = get<std::uint32_t>(d, 16);
    m.value = get<float>(d, 20);
    if (m.type == kLabel && d.size() > 32) m.label = from_utf16(d, 32);
    return m;
}

Bytes Marker::encode() const {
    Bytes d = raw;
    if (d.size() < 32) {
        d.assign(32, 0);
        put<std::uint16_t>(d, 0, 0x20);
        put<std::uint16_t>(d, 2, 1);
    }
    put(d, 4, type);
    put(d, 8, pos_us);
    put(d, 16, flag);
    put(d, 20, value);
    if (type == kLabel) {
        const bool same = d.size() > 32 && from_utf16(d, 32) == label;
        if (!same) {
            const Bytes t = to_utf16(label);
            d.resize(32);
            put<std::uint32_t>(d, 24, static_cast<std::uint32_t>(t.size() / 2));
            d.insert(d.end(), t.begin(), t.end());
        }
    }
    return d;
}

// TRKS: +0 u16 tamaño (0x20) · +2 u16 bit 0 = al revés · +4 u32 clase (1 principal, 2 overlay) ·
//       +8 i64 inicio µs · +16 i64 fin µs · +24 i64 arranque · overlays: +32 u16 2, u16 0x12 ·
//       +36 i32 compás · +40 f32 fracción · +44 f64 velocidad.
Segment Segment::decode(const Bytes& d) {
    Segment s;
    s.raw = d;
    s.reversed = (get<std::uint16_t>(d, 2) & 1) != 0;
    s.kind = get<std::uint32_t>(d, 4);
    s.src_start_us = get<std::int64_t>(d, 8);
    s.src_end_us = get<std::int64_t>(d, 16);
    s.anchor_us = get<std::int64_t>(d, 24);
    if (d.size() >= 52) {
        s.overlay_measure = get<std::int32_t>(d, 36);
        s.overlay_fraction = get<float>(d, 40);
        s.overlay_rate = get<double>(d, 44);
    }
    return s;
}

Bytes Segment::encode() const {
    Bytes d = raw;
    const std::size_t want = kind == 2 ? 52 : 32;
    if (d.size() != want) {
        Bytes n(want, 0);
        std::copy_n(d.begin(), std::min<std::size_t>(32, d.size()), n.begin());
        if (want == 52) put<std::uint16_t>(n, 32, 2), put<std::uint16_t>(n, 34, 0x12);
        d = std::move(n);
        put<std::uint16_t>(d, 0, 0x20);
    }
    const auto f = static_cast<std::uint16_t>((get<std::uint16_t>(d, 2) & ~1u) | (reversed ? 1u : 0u));
    put(d, 2, f);
    put(d, 4, kind);
    put(d, 8, src_start_us);
    put(d, 16, src_end_us);
    put(d, 24, anchor_us);
    if (want == 52) put(d, 36, overlay_measure), put(d, 40, overlay_fraction), put(d, 44, overlay_rate);
    return d;
}

// EFXT: +0 u32 36 (cabecera) · +4 identificador VST · +20 u32 hueco · +24 u32 indicadores ·
//       +28 u32 bytes de parámetros · +32 u32 caracteres del nombre con el cero ·
//       +36 parámetros f32 · luego el nombre en UTF-16.
Effect Effect::decode(const Bytes& d) {
    Effect e;
    e.raw = d;
    e.plugin_id = get<std::uint32_t>(d, 4);
    e.slot = get<std::uint32_t>(d, 20);
    e.flags = get<std::uint32_t>(d, 24);
    const std::uint32_t pbytes = get<std::uint32_t>(d, 28), nchars = get<std::uint32_t>(d, 32);
    const std::size_t hdr = get<std::uint32_t>(d, 0);
    for (std::size_t i = 0; i + 4 <= pbytes && hdr + i + 4 <= d.size(); i += 4) e.params.push_back(get<float>(d, hdr + i));
    e.name = from_utf16(d, hdr + pbytes, nchars * 2);
    return e;
}

Bytes Effect::encode() const {
    if (!raw.empty()) {
        Effect same = decode(raw);
        if (same.params.size() == params.size() && same.name == name) {
            Bytes d = raw;
            put(d, 4, plugin_id), put(d, 20, slot), put(d, 24, flags);
            const std::size_t hdr = get<std::uint32_t>(d, 0);
            for (std::size_t i = 0; i < params.size(); ++i) put(d, hdr + 4 * i, params[i]);
            return d;
        }
    }
    Bytes d(36, 0);
    put<std::uint32_t>(d, 0, 36);
    put(d, 4, plugin_id), put(d, 20, slot), put(d, 24, flags);
    const Bytes n = to_utf16(name);
    put<std::uint32_t>(d, 28, static_cast<std::uint32_t>(params.size() * 4));
    put<std::uint32_t>(d, 32, static_cast<std::uint32_t>(n.size() / 2));
    for (float v : params) d.resize(d.size() + 4), std::memcpy(&d[d.size() - 4], &v, 4);
    d.insert(d.end(), n.begin(), n.end());
    return d;
}

std::string Effect::plugin_code() const {
    std::string s(4, ' ');
    for (int i = 0; i < 4; ++i) s[static_cast<std::size_t>(i)] = static_cast<char>((plugin_id >> (24 - 8 * i)) & 0xFF);
    return s;
}

std::vector<Marker> PlaylistTrack::markers(std::uint32_t type) const {
    std::vector<Marker> out;
    for (const auto& it : layer)
        if (!it.is_segment && it.marker.type == type) out.push_back(it.marker);
    return out;
}

std::vector<Segment> PlaylistTrack::segments() const {
    std::vector<Segment> out;
    for (const auto& it : layer)
        if (it.is_segment) out.push_back(it.segment);
    return out;
}

// ------------------------------------------------------------------- lista ----------------------

namespace {

// TRKH (56 bytes): +8 identificador del audio (16) · +24 u32 BPM×1000 · +34 u16 estilo
// (1 principal, 2 overlay) · +40 f32 ajuste de tono en semitonos. El resto se conserva.
PlaylistTrack decode_track(const RiffChunk& trki) {
    PlaylistTrack t;
    for (const auto& c : trki.children) {
        if (c.id == "TRKH") {
            t.header_raw = c.data;
            std::memcpy(t.file_id.data(), c.data.data() + 8, 16);
            t.bpm = get<std::uint32_t>(c.data, 24) / 1000.0;
            t.overlay = get<std::uint16_t>(c.data, 34) == 2;
            t.key_semitones = get<float>(c.data, 40);
            if (c.data.size() >= 56) {
                t.mix_style = get<std::uint16_t>(c.data, 38);
                t.fx_view_slot = get<std::int32_t>(c.data, 48);
                t.fx_view_param = get<std::uint32_t>(c.data, 52);
            }
        } else if (c.id == "TRKF") {
            t.path = from_utf16(c.data);
        } else if (c.id == "TRSI") {
            t.transition_in = from_utf16(c.data), t.has_transition_in = true;
        } else if (c.id == "TRSO") {
            t.transition_out = from_utf16(c.data), t.has_transition_out = true;
        } else if (c.type == "TKTM") {
            for (const auto& k : c.children) {
                if (k.id == "TKTH") t.bar_us = get<std::int64_t>(k.data, 0);
                else if (k.id == "TRKM") t.beat_markers.push_back(Marker::decode(k.data)), t.tempo_order.push_back(false);
                else if (k.id == "TRKS") t.source_segments.push_back(Segment::decode(k.data)), t.tempo_order.push_back(true);
            }
        } else if (c.type == "TKEL") {
            for (const auto& k : c.children)
                if (k.id == "EFXT") t.effects.push_back(Effect::decode(k.data));
        } else if (c.type == "TKLY") {
            for (const auto& k : c.children) {
                if (k.id == "TRKM") t.layer.push_back({false, Marker::decode(k.data), {}});
                else if (k.id == "TRKS") t.layer.push_back({true, {}, Segment::decode(k.data)});
            }
        }
    }
    return t;
}

Bytes encode_header(const PlaylistTrack& t) {
    Bytes d = t.header_raw;
    if (d.size() < 56) {
        // Pista nueva: valores que MixMeister 7.8 escribe por defecto (observados).
        d.assign(56, 0);
        put<std::uint32_t>(d, 0, 0x38);
        put<std::uint16_t>(d, 32, 2);
        put<std::uint32_t>(d, 36, 0x00220001);
        put<std::uint32_t>(d, 44, 1);
        put<std::int32_t>(d, 48, -2);
    }
    std::memcpy(d.data() + 8, t.file_id.data(), 16);
    put(d, 24, static_cast<std::uint32_t>(std::llround(t.bpm * 1000)));
    put<std::uint16_t>(d, 34, t.overlay ? 2 : 1);
    put(d, 40, t.key_semitones);
    put<std::uint16_t>(d, 38, t.mix_style);
    put(d, 48, t.fx_view_slot);
    put(d, 52, t.fx_view_param);
    return d;
}

RiffChunk encode_track(const PlaylistTrack& t) {
    RiffChunk trki = list("TRKI");
    trki.children.push_back(leaf("TRKH", encode_header(t)));
    trki.children.push_back(leaf("TRKF", to_utf16(t.path)));
    if (t.has_transition_in) trki.children.push_back(leaf("TRSI", to_utf16(t.transition_in)));
    if (t.has_transition_out) trki.children.push_back(leaf("TRSO", to_utf16(t.transition_out)));
    RiffChunk tktm = list("TKTM");
    Bytes th(8, 0);
    put(th, 0, t.bar_us);
    tktm.children.push_back(leaf("TKTH", th));
    // Orden leído si sigue valiendo para lo que hay; si no, marcadores y luego segmentos.
    std::size_t nm = 0, ns = 0;
    for (bool seg : t.tempo_order) (seg ? ns : nm)++;
    if (nm == t.beat_markers.size() && ns == t.source_segments.size()) {
        std::size_t im = 0, is = 0;
        for (bool seg : t.tempo_order)
            tktm.children.push_back(seg ? leaf("TRKS", t.source_segments[is++].encode()) : leaf("TRKM", t.beat_markers[im++].encode()));
    } else {
        for (const auto& m : t.beat_markers) tktm.children.push_back(leaf("TRKM", m.encode()));
        for (const auto& s : t.source_segments) tktm.children.push_back(leaf("TRKS", s.encode()));
    }
    trki.children.push_back(std::move(tktm));
    RiffChunk tkel = list("TKEL");
    for (const auto& e : t.effects) tkel.children.push_back(leaf("EFXT", e.encode()));
    trki.children.push_back(std::move(tkel));
    RiffChunk tkly = list("TKLY");
    for (const auto& it : t.layer) tkly.children.push_back(leaf(it.is_segment ? "TRKS" : "TRKM", it.is_segment ? it.segment.encode() : it.marker.encode()));
    trki.children.push_back(std::move(tkly));
    return trki;
}

}  // namespace

Playlist parse_playlist(const Bytes& bytes) {
    Playlist p;
    p.source = parse_riff(bytes);
    if (p.source.type != "MXMP") throw std::runtime_error("no es una lista de MixMeister (RIFF/MXMP)");
    for (const auto& c : p.source.children) {
        if (c.type == "TRKL") {
            for (const auto& k : c.children)
                if (k.type == "TRKI") p.tracks.push_back(decode_track(k));
        } else if (c.type == "GLBL") {
            for (const auto& k : c.children) {
                if (k.id == "GBIN") p.master_gain_db = get<float>(k.data, 4);
                else if (k.id == "EFXT") p.master_effects.push_back(Effect::decode(k.data));
            }
        } else if (c.id == "MMVR" && c.data.size() >= 12) {
            p.version = {get<std::uint32_t>(c.data, 4), get<std::uint32_t>(c.data, 8)};
        }
    }
    return p;
}

Playlist read_playlist(const std::string& path) { return parse_playlist(read_file(path)); }

void renumber_effects(PlaylistTrack& t, const std::vector<std::pair<std::uint32_t, std::uint32_t>>& map) {
    auto to = [&](std::uint32_t old, bool& found) {
        for (const auto& [a, b] : map) if (a == old) { found = true; return b; }
        found = false;
        return old;
    };
    for (auto& e : t.effects) { bool f; e.slot = to(e.slot, f); }
    for (auto& it : t.layer) {
        if (it.is_segment || it.marker.type != kEffectParam) continue;
        bool f;
        const std::uint32_t s = to(it.marker.flag >> 12, f);
        if (f) it.marker.flag = (s << 12) | (it.marker.flag & 0xFFF);
    }
    if (t.fx_view_slot > 0) { bool f; const auto s = to(static_cast<std::uint32_t>(t.fx_view_slot), f); if (f) t.fx_view_slot = static_cast<std::int32_t>(s); }
}

Bytes encode_tweak(PlaylistTrack t) {
    std::vector<std::pair<std::uint32_t, std::uint32_t>> map;
    for (std::size_t i = 0; i < t.effects.size(); ++i) map.emplace_back(t.effects[i].slot, static_cast<std::uint32_t>(2 + i));
    renumber_effects(t, map);
    RiffChunk root;
    root.id = "RIFF";
    root.type = "MMDM";
    RiffChunk trki = encode_track(t);
    root.children = trki.children;
    for (const auto& c : trki.children)
        if (c.type == "TKLY") for (const auto& k : c.children) root.children.push_back(k);
    return serialize_riff(root);
}

PlaylistTrack decode_tweak(const Bytes& bytes) {
    const RiffChunk root = parse_riff(bytes);
    if (root.type != "MMDM") throw std::runtime_error("no es un Tweak de MixMeister (RIFF/MMDM)");
    return decode_track(root);   // los TRKM/TRKS sueltos del final no son hijos que lea decode_track
}

Bytes serialize_playlist(const Playlist& p) {
    RiffChunk root;
    root.id = "RIFF";
    root.type = "MXMP";
    RiffChunk trkl = list("TRKL");
    for (const auto& t : p.tracks) trkl.children.push_back(encode_track(t));
    RiffChunk glbl = list("GLBL");
    Bytes gb(8, 0);
    put<std::uint32_t>(gb, 0, 8);
    put(gb, 4, p.master_gain_db);
    glbl.children.push_back(leaf("GBIN", gb));
    for (const auto& e : p.master_effects) glbl.children.push_back(leaf("EFXT", e.encode()));
    Bytes vr(12, 0);
    put<std::uint32_t>(vr, 0, 12), put(vr, 4, p.version[0]), put(vr, 8, p.version[1]);
    RiffChunk mmvr = leaf("MMVR", vr);

    // Orden de los bloques de primer nivel: el del fichero leído; bloques que no conocemos, se
    // conservan en su sitio.
    if (p.source.children.empty()) {
        root.children = {std::move(trkl), std::move(glbl), std::move(mmvr)};
    } else {
        for (const auto& c : p.source.children) {
            if (c.type == "TRKL") root.children.push_back(trkl);
            else if (c.type == "GLBL") {
                // GBIN y EFXT van en el orden en que estaban.
                RiffChunk g = list("GLBL");
                std::size_t e = 0;
                bool gbin = false;
                for (const auto& k : c.children) {
                    if (k.id == "GBIN") g.children.push_back(glbl.children[0]), gbin = true;
                    else if (k.id == "EFXT") { if (e < p.master_effects.size()) g.children.push_back(leaf("EFXT", p.master_effects[e++].encode())); }
                    else g.children.push_back(k);
                }
                if (!gbin) g.children.insert(g.children.begin(), glbl.children[0]);
                for (; e < p.master_effects.size(); ++e) g.children.push_back(leaf("EFXT", p.master_effects[e].encode()));
                root.children.push_back(std::move(g));
            } else if (c.id == "MMVR") root.children.push_back(mmvr);
            else root.children.push_back(c);
        }
        if (!p.source.find("TRKL")) root.children.insert(root.children.begin(), trkl);
        if (!p.source.find("GLBL")) root.children.push_back(glbl);
        if (!p.source.find("MMVR")) root.children.push_back(mmvr);
    }
    return serialize_riff(root);
}

void write_playlist(const std::string& path, const Playlist& p) { write_file(path, serialize_playlist(p)); }

// ------------------------------------------------------------------- compatibilidad -------------

std::vector<MmpTrack> read_mmp(const std::string& path) {
    const Playlist p = read_playlist(path);
    std::vector<MmpTrack> out;
    for (const auto& t : p.tracks) {
        MmpTrack m;
        m.path = t.path;
        m.transition_in = t.transition_in;
        m.transition_out = t.transition_out;
        m.hash = t.file_id;
        m.tempo_markers = t.beat_markers.size();
        out.push_back(std::move(m));
    }
    return out;
}

std::string resolve_track(const std::string& stored, const std::vector<std::string>& dirs) {
    namespace fs = std::filesystem;
    std::error_code ec;
    if (fs::exists(stored, ec)) return stored;
    const auto cut = stored.find_last_of("\\/");
    const std::string want = lower(cut == std::string::npos ? stored : stored.substr(cut + 1));
    for (const auto& dir : dirs) {
        for (auto it = fs::recursive_directory_iterator(dir, fs::directory_options::skip_permission_denied, ec);
             it != fs::recursive_directory_iterator(); it.increment(ec)) {
            if (ec) break;
            if (it->is_regular_file(ec) && lower(it->path().filename().string()) == want) return it->path().string();
        }
    }
    return {};
}

}  // namespace mmn
