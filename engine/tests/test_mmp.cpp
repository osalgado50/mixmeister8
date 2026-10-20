// Lector de sesiones .mmp sobre un fichero construido aquí (sin ficheros de MixMeister).
#include "doctest.h"
#include "mmn/mmp.hpp"

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

using namespace mmn;

namespace {

void put32(std::string& s, std::uint32_t v) { s.append(reinterpret_cast<const char*>(&v), 4); }
std::string chunk(const std::string& id, const std::string& body) {
    std::string s = id;
    put32(s, static_cast<std::uint32_t>(body.size()));
    s += body;
    if (body.size() & 1) s += '\0';
    return s;
}
std::string list(const std::string& type, const std::string& body) { return chunk("LIST", type + body); }
std::string u16(const std::string& ascii) {
    std::string s;
    for (char c : ascii) s += c, s += '\0';
    return s + std::string(2, '\0');
}

}  // namespace

TEST_CASE("Lee pistas, rutas y transiciones de una sesión .mmp") {
    std::string trkh(56, '\0');
    for (int i = 0; i < 16; ++i) trkh[8 + i] = static_cast<char>(i + 1);
    std::string marks = chunk("TKTH", std::string(8, '\0'));
    for (int i = 0; i < 3; ++i) marks += chunk("TRKM", std::string(32, '\0'));
    const std::string t1 = list("TRKI", chunk("TRKH", trkh) + chunk("TRKF", u16("C:\\Musica\\Uno.mp3")) +
                                            chunk("TRSO", u16("Beatmix Full")) + list("TKTM", marks) +
                                            list("TKLY", chunk("TRKM", std::string(32, '\0'))));
    const std::string t2 = list("TRKI", chunk("TRKH", trkh) + chunk("TRKF", u16("D:\\Otra\\Dos.mp3")) +
                                            chunk("TRSI", u16("Beatmix Full")));
    const std::string riff = chunk("RIFF", "MXMP" + list("TRKL", t1 + t2));
    const auto path = (std::filesystem::temp_directory_path() / "mmn_test.mmp").string();
    std::ofstream(path, std::ios::binary) << riff;
    const auto tr = read_mmp(path);
    std::remove(path.c_str());
    REQUIRE(tr.size() == 2);
    CHECK(tr[0].path == "C:\\Musica\\Uno.mp3");
    CHECK(tr[0].transition_out == "Beatmix Full");
    CHECK(tr[0].tempo_markers == 3);  // el de TKLY (bucle) no cuenta
    CHECK(tr[0].hash[0] == 1);
    CHECK(tr[1].path == "D:\\Otra\\Dos.mp3");
    CHECK(tr[1].transition_in == "Beatmix Full");
}

TEST_CASE("Encuentra el audio por su nombre aunque la ruta de Windows ya no exista") {
    namespace fs = std::filesystem;
    const auto dir = fs::temp_directory_path() / "mmn_busca" / "sub";
    fs::create_directories(dir);
    std::ofstream(dir / "Tema Uno.MP3") << "x";
    const auto got = resolve_track("C:\\Club\\tema uno.mp3", {(fs::temp_directory_path() / "mmn_busca").string()});
    CHECK(fs::path(got).filename() == "Tema Uno.MP3");
    CHECK(resolve_track("C:\\no\\existe.mp3", {(fs::temp_directory_path() / "mmn_busca").string()}).empty());
    fs::remove_all(fs::temp_directory_path() / "mmn_busca");
}

TEST_CASE("Una lista creada desde cero se escribe y se vuelve a leer igual") {
    Playlist p;
    PlaylistTrack t;
    t.path = "/Música/Señorita – ñandú 🎵.mp3";  // acentos, guion largo y un emoji (par sustituto)
    t.has_transition_out = true;
    t.transition_out = "Beatmix 8";
    t.bpm = 128.004;
    t.bar_us = 1875000;  // 128 BPM
    t.key_semitones = -1.5f;
    for (int i = 0; i < 16; ++i) t.file_id[static_cast<std::size_t>(i)] = static_cast<std::uint8_t>(0xA0 + i);
    Marker in{kIntroAnchor, 11000, 0, 0, {}, {}};
    Marker vol{kVolume, 2'000'000, 1, -6, {}, {}};
    Marker lab{kLabel, 3'000'000, 0, 0, "Estribillo", {}};
    Segment s;
    s.src_end_us = 180'000'000;
    t.layer = {{false, in, {}}, {false, vol, {}}, {false, lab, {}}, {true, {}, s}};
    p.tracks.push_back(t);
    PlaylistTrack o;  // overlay
    o.path = "C:\\Loops\\drums.wav";
    o.overlay = true;
    Segment os;
    os.kind = 2;
    os.src_end_us = 3'427'000;
    os.overlay_measure = 116;
    os.overlay_fraction = 0.849f;
    o.layer = {{true, {}, os}};
    p.tracks.push_back(o);
    p.master_gain_db = -0.9f;

    const auto bytes = serialize_playlist(p);
    const Playlist q = parse_playlist(bytes);
    REQUIRE(q.tracks.size() == 2);
    CHECK(q.tracks[0].path == t.path);
    CHECK(q.tracks[0].transition_out == "Beatmix 8");
    CHECK(!q.tracks[0].has_transition_in);
    CHECK(q.tracks[0].bpm == doctest::Approx(128.004));
    CHECK(q.tracks[0].original_bpm() == doctest::Approx(128.0));
    CHECK(q.tracks[0].key_semitones == -1.5f);
    CHECK(q.tracks[0].file_id == t.file_id);
    CHECK(q.tracks[0].markers(kVolume).at(0).value == -6.0f);
    CHECK(q.tracks[0].markers(kLabel).at(0).label == "Estribillo");
    CHECK(q.tracks[0].segments().at(0).src_end_us == 180'000'000);
    CHECK(q.tracks[1].overlay);
    CHECK(q.tracks[1].segments().at(0).overlay_measure == 116);
    CHECK(q.master_gain_db == -0.9f);
    CHECK(serialize_playlist(q) == bytes);  // estable: escribir lo leído no cambia nada
}

TEST_CASE("Editar un campo solo cambia ese campo") {
    Playlist p;
    PlaylistTrack t;
    t.path = "a.mp3";
    Marker lab{kLabel, 1000, 0, 0, "1", {}};
    t.layer = {{false, lab, {}}};
    p.tracks.push_back(t);
    Playlist q = parse_playlist(serialize_playlist(p));
    q.tracks[0].layer[0].marker.label = "Subida final";
    q.tracks[0].layer[0].marker.pos_us = 5000;
    q.tracks[0].key_semitones = 2;
    const Playlist r = parse_playlist(serialize_playlist(q));
    CHECK(r.tracks[0].markers(kLabel).at(0).label == "Subida final");
    CHECK(r.tracks[0].markers(kLabel).at(0).pos_us == 5000);
    CHECK(r.tracks[0].key_semitones == 2.0f);
    CHECK(r.tracks[0].path == "a.mp3");
}
