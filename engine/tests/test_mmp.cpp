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
