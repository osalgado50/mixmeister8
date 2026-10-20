#include "mmn/mmp.hpp"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>

namespace mmn {
namespace {

std::uint32_t u32(const std::vector<std::uint8_t>& d, std::size_t p) {
    if (p + 4 > d.size()) throw std::out_of_range("mmp: lectura fuera del fichero");
    std::uint32_t v;
    std::memcpy(&v, d.data() + p, 4);
    return v;
}

/// UTF-16LE → UTF-8, hasta el primer cero.
std::string utf16(const std::vector<std::uint8_t>& d, std::size_t p, std::size_t len) {
    std::string out;
    for (std::size_t i = 0; i + 1 < len; i += 2) {
        std::uint32_t c = d[p + i] | (d[p + i + 1] << 8);
        if (c == 0) break;
        if (c >= 0xD800 && c < 0xDC00 && i + 3 < len) {  // par sustituto
            const std::uint32_t lo = d[p + i + 2] | (d[p + i + 3] << 8);
            c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
            i += 2;
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

void walk(const std::vector<std::uint8_t>& d, std::size_t p, std::size_t end, std::vector<MmpTrack>& out, MmpTrack* cur,
          const std::string& list = {}) {
    while (p + 8 <= end) {
        const std::string id(reinterpret_cast<const char*>(&d[p]), 4);
        const std::size_t len = u32(d, p + 4), body = p + 8;
        if (body + len > d.size()) break;
        if (id == "LIST" && len >= 4) {
            const std::string type(reinterpret_cast<const char*>(&d[body]), 4);
            if (type == "TRKI") {
                out.emplace_back();
                walk(d, body + 4, body + len, out, &out.back(), type);
            } else {
                walk(d, body + 4, body + len, out, cur, type);
            }
        } else if (cur) {
            if (id == "TRKF") cur->path = utf16(d, body, len);
            else if (id == "TRSI") cur->transition_in = utf16(d, body, len);
            else if (id == "TRSO") cur->transition_out = utf16(d, body, len);
            else if (id == "TRKH" && len >= 24) std::memcpy(cur->hash.data(), &d[body + 8], 16);
            else if (id == "TRKM" && list == "TKTM") ++cur->tempo_markers;
        }
        p = body + len + (len & 1);
    }
}

std::string lower(std::string s) {
    for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

}  // namespace

std::vector<MmpTrack> read_mmp(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("no se puede abrir: " + path);
    const std::vector<std::uint8_t> d{std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
    if (d.size() < 12 || std::memcmp(d.data(), "RIFF", 4) || std::memcmp(d.data() + 8, "MXMP", 4))
        throw std::runtime_error("no es una sesión .mmp (RIFF/MXMP): " + path);
    std::vector<MmpTrack> out;
    walk(d, 12, d.size(), out, nullptr);
    return out;
}

std::string resolve_track(const std::string& stored, const std::vector<std::string>& dirs) {
    namespace fs = std::filesystem;
    std::error_code ec;
    if (fs::exists(stored, ec)) return stored;
    // Nombre de fichero: lo que va tras la última \ o /.
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
