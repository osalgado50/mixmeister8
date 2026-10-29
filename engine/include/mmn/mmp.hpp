// mmn/mmp.hpp — listas de MixMeister (.mmp, RIFF "MXMP"): lectura y escritura sin pérdidas.
//
// Formato estudiado por interoperabilidad (Directiva 2009/24/CE, art. 6) observando ficheros
// guardados por MixMeister; especificación completa en docs/spec/mmp.md. Dos capas:
//
//   1. `Riff`: el árbol de bloques tal cual. Leer y volver a escribir sin tocar nada da el mismo
//      fichero byte a byte (comprobado contra 627 listas reales de 2008 a 2026).
//   2. `Playlist`: lo que significa — pistas, segmentos, marcadores, tempo, efectos. Cada pieza
//      guarda sus bytes originales y solo reescribe los campos que se cambian, así que lo que aún
//      no entendemos sobrevive a una edición.
#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace mmn {

// ---------------------------------------------------------------- capa 1: árbol RIFF ----------

struct RiffChunk {
    std::string id;                      ///< "TRKH", "LIST"…
    std::string type;                    ///< solo LIST/RIFF: "TRKI", "MXMP"…
    std::vector<std::uint8_t> data;      ///< solo hojas
    std::vector<RiffChunk> children;     ///< solo LIST/RIFF
    bool is_list() const { return id == "LIST" || id == "RIFF"; }
    const RiffChunk* find(const std::string& id_or_type) const;
};

/// Lanza std::runtime_error si el fichero no es RIFF bien formado.
RiffChunk parse_riff(const std::vector<std::uint8_t>& bytes);
std::vector<std::uint8_t> serialize_riff(const RiffChunk& root);

std::vector<std::uint8_t> read_file(const std::string& path);
void write_file(const std::string& path, const std::vector<std::uint8_t>& bytes);

/// UTF-16LE con cero final ⇄ UTF-8.
std::string from_utf16(const std::vector<std::uint8_t>& d, std::size_t off = 0, std::size_t len = SIZE_MAX);
std::vector<std::uint8_t> to_utf16(const std::string& utf8);

// ---------------------------------------------------------------- capa 2: significado ---------

/// Tipos de marcador (TRKM, campo +4). Confirmados añadiendo cada uno en MixMeister y comparando.
enum MarkerType : std::uint32_t {
    kIntroAnchor = 0x00000001,      ///< ancla de entrada (donde empieza la mezcla con la anterior)
    kOutroAnchor = 0x00000002,      ///< ancla de salida
    kAutoVolumeIn = 0x00000080,     ///< volumen que pone la mezcla por defecto (entrada)
    kAutoVolume = 0x00000100,       ///< volumen que pone la mezcla por defecto (fundido de salida)
    kVolume = 0x00008000,           ///< Add Volume Marker (dB)
    kTreble = 0x00010000,           ///< Add Treble Marker (dB)
    kMidrange = 0x00020000,         ///< Add Midrange Marker (dB)
    kBass = 0x00040000,             ///< Add Bass Marker (dB)
    kTempo = 0x01000000,            ///< Add Tempo Marker (BPM)
    kOriginalTempo = 0x02000000,    ///< Add Original Tempo Marker (BPM)
    kLabel = 0x04000000,            ///< Add Label Marker (texto)
    kEffectParam = 0x08000000,      ///< Add Effects Parameter Marker
    kMeasure = 0x10000000,          ///< marcador de compás del Beat Slicer
    kLoopStart = 0x40000000,        ///< Add Loop Start Marker
    kLoopEnd = 0x80000000,          ///< Add Loop End Marker
};
const char* marker_name(std::uint32_t type);

struct Marker {
    std::uint32_t type = 0;
    std::int64_t pos_us = 0;        ///< microsegundos en el audio original
    std::uint32_t flag = 0;         ///< +16 (0/1); en volumen/EQ, 1 = punto ya ajustado por el usuario
    float value = 0;                ///< dB, BPM… según el tipo
    std::string label;              ///< solo kLabel
    std::vector<std::uint8_t> raw;  ///< bytes originales (vacío si es nuevo)
    std::vector<std::uint8_t> encode() const;
    static Marker decode(const std::vector<std::uint8_t>& d);
};

/// Segmento de pista (TRKS). Una pista empieza con uno; «Split Segment at Cursor» la parte en dos.
struct Segment {
    bool reversed = false;          ///< «Reverse»: se reproduce desde src_end hacia src_start
    std::uint32_t kind = 1;         ///< 1 pista principal, 2 overlay (lleva los campos de abajo)
    std::int64_t src_start_us = 0, src_end_us = 0;
    std::int64_t anchor_us = 0;     ///< punto de arranque: src_start, o src_end si va al revés
    // Solo overlays (52 bytes):
    std::int32_t overlay_measure = 0;  ///< compás de la mezcla donde cae
    float overlay_fraction = 0;        ///< fracción de compás
    double overlay_rate = 1.0;
    std::vector<std::uint8_t> raw;
    std::vector<std::uint8_t> encode() const;
    static Segment decode(const std::vector<std::uint8_t>& d);
};

/// Efecto VST de una pista o del master (EFXT).
struct Effect {
    std::uint32_t plugin_id = 0;    ///< identificador VST de 4 caracteres
    std::uint32_t slot = 0;         ///< +20
    std::uint32_t flags = 0;        ///< +24
    std::vector<float> params;      ///< valores normalizados 0..1
    std::string name;
    std::vector<std::uint8_t> raw;
    std::string plugin_code() const;  ///< "NdrV"… legible
    std::vector<std::uint8_t> encode() const;
    static Effect decode(const std::vector<std::uint8_t>& d);
};

struct PlaylistTrack {
    std::string path;               ///< ruta guardada (Windows o Mac, tal cual)
    std::string transition_in, transition_out;  ///< vacías si no hay TRSI/TRSO
    bool has_transition_in = false, has_transition_out = false;
    std::array<std::uint8_t, 16> file_id{};     ///< identifica el audio (= ZMUSICFILEID del catálogo)
    double bpm = 0;                 ///< TRKH +24 / 1000
    bool overlay = false;           ///< Track Settings → Overlay Track
    float key_semitones = 0;        ///< Track Settings → Key Adjustment
    /// TRKH +48/+52: efecto (instancia) y parámetro cuyos Effects Parameter Markers se ven en la
    /// pista (−2 = ninguno; 0xFFF = Enable/Bypass). Comprobado: al añadir un efecto MixMeister pone
    /// su instancia y 0xFFF; en 10 473 pistas sin efectos vale −2.
    std::int32_t fx_view_slot = -2;
    std::uint32_t fx_view_param = 0;
    /// TRKH +38: estilo de mezcla de la pista (0x22 beatmix, 0x11 simple; experimento Preset - Simple).
    std::uint16_t mix_style = 0x22;
    std::vector<std::uint8_t> header_raw;  ///< TRKH completo (56 bytes)

    // Mapa de tempo original (TKTM): duración del compás y marcadores del Beat Slicer.
    std::int64_t bar_us = 0;        ///< TKTH: microsegundos por compás; BPM = 240e6 / bar_us
    std::vector<Marker> beat_markers;
    std::vector<Segment> source_segments;  ///< TRKS de TKTM (la pista entera)
    std::vector<bool> tempo_order;  ///< orden leído en TKTM (true = TRKS); se respeta al escribir

    std::vector<Effect> effects;    ///< TKEL
    // Capa de mezcla (TKLY): marcadores y segmentos, en el orden en que estaban.
    struct LayerItem { bool is_segment; Marker marker; Segment segment; };
    std::vector<LayerItem> layer;

    double original_bpm() const { return bar_us > 0 ? 240e6 / static_cast<double>(bar_us) : 0; }
    std::vector<Marker> markers(std::uint32_t type) const;
    std::vector<Segment> segments() const;
};

struct Playlist {
    std::vector<PlaylistTrack> tracks;
    float master_gain_db = 0;              ///< GBIN
    std::vector<Effect> master_effects;    ///< GLBL/EFXT
    std::array<std::uint32_t, 2> version{0x00070000, 0x00040001};  ///< MMVR (la que escribe 7.8)
    RiffChunk source;                      ///< árbol leído: lo no interpretado se conserva desde aquí
};

Playlist read_playlist(const std::string& path);
Playlist parse_playlist(const std::vector<std::uint8_t>& bytes);
/// Vuelve a montar el fichero desde el modelo. Sin cambios en el modelo, sale idéntico al leído.
std::vector<std::uint8_t> serialize_playlist(const Playlist& p);
void write_playlist(const std::string& path, const Playlist& p);

// ---------------------------------------------------------------- Tweaks ---------------------
// Un Tweak (ZTRACKPRESET.ZTRACKPRESETDATA en la biblioteca) es RIFF "MMDM" con el contenido de la
// pista tal como va en la lista (TRKH, TRKF, TRSI/TRSO, TKTM, TKEL, TKLY) y, detrás, otra vez los
// marcadores y segmentos de TKLY sueltos. Los efectos se renumeran desde 2 (con sus marcadores y
// TRKH +48). Comprobado con un Tweak guardado por MixMeister 7.8 (docs/spec/mmp.md).
std::vector<std::uint8_t> encode_tweak(PlaylistTrack t);
PlaylistTrack decode_tweak(const std::vector<std::uint8_t>& bytes);
/// Cambia los números de instancia de los efectos de la pista (`map[viejo] = nuevo`) en los EFXT,
/// en sus Effects Parameter Markers y en TRKH +48.
void renumber_effects(PlaylistTrack& t, const std::vector<std::pair<std::uint32_t, std::uint32_t>>& map);

// ---------------------------------------------------------------- compatibilidad --------------

struct MmpTrack {
    std::string path;
    std::string transition_in, transition_out;
    std::array<std::uint8_t, 16> hash{};
    std::size_t tempo_markers = 0;
};
/// Resumen por pista (para el render de sesiones). Lanza std::runtime_error si no es RIFF/MXMP.
std::vector<MmpTrack> read_mmp(const std::string& path);

/// Encuentra el audio de una pista aunque la ruta guardada ya no exista (otra máquina, otro
/// disco, Windows): primero la ruta tal cual; si no, el mismo nombre de fichero (sin distinguir
/// mayúsculas) dentro de `search_dirs`, recursivamente. Vacío si no aparece.
std::string resolve_track(const std::string& stored, const std::vector<std::string>& search_dirs);

}  // namespace mmn
