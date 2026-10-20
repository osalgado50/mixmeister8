#include "mmn/mxm.hpp"

#include <cstring>
#include <fstream>
#include <iterator>
#include <stdexcept>

namespace mmn {
namespace {

template <class T> T rd(const std::vector<std::uint8_t>& d, std::size_t p) {
    if (p + sizeof(T) > d.size()) throw std::out_of_range("mxm: lectura fuera del bloque");
    T v;
    std::memcpy(&v, d.data() + p, sizeof v);
    return v;
}

/// Intenta leer 4 arrays [contador][contador × u64] con contadores de `w` bytes.
bool parse_arrays(const std::vector<std::uint8_t>& d, std::size_t p, int w, std::uint64_t limit,
                  std::vector<std::vector<std::uint64_t>>& out) {
    out.clear();
    for (int a = 0; a < 4; ++a) {
        if (p + w > d.size()) return false;
        const std::uint64_t n = w == 8 ? rd<std::uint64_t>(d, p) : rd<std::uint32_t>(d, p);
        p += w;
        if (n > 4096 || p + n * 8 > d.size()) return false;
        std::vector<std::uint64_t> v(n);
        for (auto& x : v) {
            x = rd<std::uint64_t>(d, p);
            p += 8;
            if (x > limit) return false;
        }
        out.push_back(std::move(v));
    }
    return true;
}

}  // namespace

Mxm read_mxm(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("no se puede abrir: " + path);
    const std::vector<std::uint8_t> d{std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
    if (d.size() < 12 || std::memcmp(d.data(), "RIFF", 4) || std::memcmp(d.data() + 8, "MXM6", 4))
        throw std::runtime_error("no es un .mxm (RIFF/MXM6): " + path);
    Mxm m;
    for (std::size_t p = 12; p + 8 <= d.size();) {
        const std::string id(reinterpret_cast<const char*>(&d[p]), 4);
        const auto len = rd<std::uint32_t>(d, p + 4);
        const std::size_t body = p + 8;
        if (body + len > d.size()) break;
        m.chunks.push_back(id);
        const std::vector<std::uint8_t> c(d.begin() + body, d.begin() + body + len);
        if (id == "info" && len >= 18) {
            m.format_version = rd<std::uint32_t>(c, 0);
            m.info_rate = rd<std::uint32_t>(c, 4);
            m.info_samples = rd<std::uint64_t>(c, 10);
        } else if (id == "prof" && len >= 52) {
            MxmProfile pr;
            pr.version = rd<std::uint32_t>(c, 0);
            pr.sample_rate = rd<std::uint32_t>(c, 4);
            pr.bpm = rd<float>(c, 8);
            pr.confidence = rd<float>(c, 12);
            pr.region_begin = rd<std::uint64_t>(c, 24);
            pr.region_end = rd<std::uint64_t>(c, 32);
            pr.total_samples = rd<std::uint64_t>(c, 40);
            pr.bitrate = rd<std::uint32_t>(c, 48);
            const std::uint64_t limit = pr.total_samples * 2 + 1'000'000;
            for (int w : {8, 4})
                if (parse_arrays(c, 52, w, limit, pr.arrays)) {
                    pr.counter_width = w;
                    break;
                }
            m.prof = std::move(pr);
        }
        p = body + len + (len & 1);
    }
    return m;
}

}  // namespace mmn
