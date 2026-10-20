// Lectura y escritura de audio. MP3 vía minimp3 (CC0); WAV con lector propio;
// en macOS, AAC/M4A/ALAC/AIFF/FLAC vía AudioToolbox (el decodificador del sistema).
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_FLOAT_OUTPUT
#include "minimp3_ex.h"

#include "mmn/audio.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <numbers>
#include <stdexcept>

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#endif

namespace mmn {
namespace {

std::vector<std::uint8_t> slurp(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("no se puede abrir: " + path);
    return {std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}

template <class T> T rd(const std::uint8_t* p) {
    T v;
    std::memcpy(&v, p, sizeof v);
    return v;
}

Buffer decode_wav(const std::vector<std::uint8_t>& d, const std::string& path) {
    if (d.size() < 12 || std::memcmp(d.data(), "RIFF", 4) || std::memcmp(d.data() + 8, "WAVE", 4))
        throw std::runtime_error("WAV no válido: " + path);
    int fmt = 0, chans = 0, rate = 0, bits = 0;
    const std::uint8_t* data = nullptr;
    std::size_t data_len = 0;
    for (std::size_t p = 12; p + 8 <= d.size();) {
        auto len = rd<std::uint32_t>(&d[p + 4]);
        const std::uint8_t* body = &d[p + 8];
        std::size_t avail = std::min<std::size_t>(len, d.size() - p - 8);
        if (!std::memcmp(&d[p], "fmt ", 4) && avail >= 16) {
            fmt = rd<std::uint16_t>(body);
            chans = rd<std::uint16_t>(body + 2);
            rate = static_cast<int>(rd<std::uint32_t>(body + 4));
            bits = rd<std::uint16_t>(body + 14);
            if (fmt == 0xFFFE && avail >= 26) fmt = rd<std::uint16_t>(body + 24);  // extensible
        } else if (!std::memcmp(&d[p], "data", 4)) {
            data = body;
            data_len = avail;
        }
        p += 8 + len + (len & 1);
    }
    if (!data || chans <= 0 || rate <= 0) throw std::runtime_error("WAV sin fmt/data: " + path);
    if (!((fmt == 1 && (bits == 16 || bits == 24 || bits == 32)) || (fmt == 3 && bits == 32)))
        throw std::runtime_error("formato WAV no soportado: " + path);
    const int bps = bits / 8;
    const std::size_t n = data_len / (static_cast<std::size_t>(bps) * chans);
    Buffer b;
    b.sample_rate = rate;
    b.ch.assign(chans, std::vector<float>(n));
    for (std::size_t i = 0; i < n; ++i)
        for (int c = 0; c < chans; ++c) {
            const std::uint8_t* s = data + (i * chans + c) * bps;
            float v;
            if (fmt == 3) v = rd<float>(s);
            else if (bits == 16) v = rd<std::int16_t>(s) / 32768.0f;
            else if (bits == 24) v = static_cast<float>((std::int32_t(s[0] << 8 | s[1] << 16 | s[2] << 24)) >> 8) / 8388608.0f;
            else v = static_cast<float>(rd<std::int32_t>(s) / 2147483648.0);
            b.ch[c][i] = v;
        }
    return b;
}

Buffer decode_mp3(const std::vector<std::uint8_t>& d, const std::string& path) {
    mp3dec_t dec;
    mp3dec_file_info_t info{};
    if (mp3dec_load_buf(&dec, d.data(), d.size(), &info, nullptr, nullptr) || !info.buffer || info.channels <= 0) {
        std::free(info.buffer);
        throw std::runtime_error("MP3 no decodificable: " + path);
    }
    Buffer b;
    b.sample_rate = info.hz;
    const std::size_t n = info.samples / info.channels;
    b.ch.assign(info.channels, std::vector<float>(n));
    for (std::size_t i = 0; i < n; ++i)
        for (int c = 0; c < info.channels; ++c) b.ch[c][i] = info.buffer[i * info.channels + c];
    std::free(info.buffer);
    return b;
}

double bessel_i0(double x) {
    double s = 1, t = 1;
    for (int k = 1; k < 40; ++k) {
        t *= (x / (2 * k)) * (x / (2 * k));
        s += t;
        if (t < 1e-12 * s) break;
    }
    return s;
}


#if defined(__APPLE__)
/// Cualquier formato que entienda Core Audio, convertido a float32 entrelazado.
Buffer decode_core_audio(const std::string& path) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        nullptr, reinterpret_cast<const UInt8*>(path.c_str()), static_cast<CFIndex>(path.size()), false);
    if (!url) throw std::runtime_error("ruta no válida: " + path);
    ExtAudioFileRef f = nullptr;
    const OSStatus st = ExtAudioFileOpenURL(url, &f);
    CFRelease(url);
    if (st != noErr || !f) throw std::runtime_error("Core Audio no puede abrir: " + path);
    struct Closer { ExtAudioFileRef f; ~Closer() { ExtAudioFileDispose(f); } } closer{f};

    AudioStreamBasicDescription in{};
    UInt32 sz = sizeof in;
    if (ExtAudioFileGetProperty(f, kExtAudioFileProperty_FileDataFormat, &sz, &in) != noErr || in.mChannelsPerFrame == 0)
        throw std::runtime_error("formato desconocido: " + path);
    const UInt32 ch = in.mChannelsPerFrame;
    AudioStreamBasicDescription out{};
    out.mSampleRate = in.mSampleRate;
    out.mFormatID = kAudioFormatLinearPCM;
    out.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    out.mChannelsPerFrame = ch;
    out.mBitsPerChannel = 32;
    out.mBytesPerFrame = 4 * ch;
    out.mFramesPerPacket = 1;
    out.mBytesPerPacket = out.mBytesPerFrame;
    if (ExtAudioFileSetProperty(f, kExtAudioFileProperty_ClientDataFormat, sizeof out, &out) != noErr)
        throw std::runtime_error("no se puede convertir a PCM: " + path);

    Buffer b;
    b.sample_rate = static_cast<int>(std::lround(in.mSampleRate));
    b.ch.assign(ch, {});
    constexpr UInt32 kChunk = 32768;
    std::vector<float> tmp(static_cast<std::size_t>(kChunk) * ch);
    for (;;) {
        AudioBufferList abl{};
        abl.mNumberBuffers = 1;
        abl.mBuffers[0].mNumberChannels = ch;
        abl.mBuffers[0].mDataByteSize = static_cast<UInt32>(tmp.size() * sizeof(float));
        abl.mBuffers[0].mData = tmp.data();
        UInt32 frames = kChunk;
        if (ExtAudioFileRead(f, &frames, &abl) != noErr) throw std::runtime_error("error al decodificar: " + path);
        if (frames == 0) break;
        for (UInt32 c = 0; c < ch; ++c) {
            auto& dst = b.ch[c];
            const std::size_t base = dst.size();
            dst.resize(base + frames);
            for (UInt32 i = 0; i < frames; ++i) dst[base + i] = tmp[static_cast<std::size_t>(i) * ch + c];
        }
    }
    if (b.frames() == 0) throw std::runtime_error("sin audio: " + path);
    return b;
}
#endif

}  // namespace

Buffer read_audio(const std::string& path) {
    auto d = slurp(path);
    if (d.size() >= 12 && !std::memcmp(d.data(), "RIFF", 4) && !std::memcmp(d.data() + 8, "WAVE", 4))
        return decode_wav(d, path);
#if defined(__APPLE__)
    // Contenedor MP4 (m4a/aac/alac): 'ftyp' en el byte 4. AIFF: 'FORM'. FLAC: 'fLaC'.
    const bool mp4 = d.size() >= 8 && !std::memcmp(d.data() + 4, "ftyp", 4);
    const bool other = d.size() >= 4 && (!std::memcmp(d.data(), "FORM", 4) || !std::memcmp(d.data(), "fLaC", 4));
    if (mp4 || other) return decode_core_audio(path);
#endif
    return decode_mp3(d, path);
}

void write_wav16(const std::string& path, const Buffer& b) {
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("no se puede escribir: " + path);
    const std::uint32_t n = static_cast<std::uint32_t>(b.frames()), c = b.channels();
    const std::uint32_t data = n * c * 2, rate = b.sample_rate;
    auto u32 = [&](std::uint32_t v) { f.write(reinterpret_cast<const char*>(&v), 4); };
    auto u16 = [&](std::uint16_t v) { f.write(reinterpret_cast<const char*>(&v), 2); };
    f.write("RIFF", 4); u32(36 + data); f.write("WAVEfmt ", 8); u32(16);
    u16(1); u16(static_cast<std::uint16_t>(c)); u32(rate); u32(rate * c * 2); u16(static_cast<std::uint16_t>(c * 2)); u16(16);
    f.write("data", 4); u32(data);
    std::vector<std::int16_t> row(c);
    for (std::uint32_t i = 0; i < n; ++i) {
        for (std::uint32_t k = 0; k < c; ++k)
            row[k] = static_cast<std::int16_t>(std::lrint(std::clamp(b.ch[k][i], -1.0f, 1.0f) * 32767.0f));
        f.write(reinterpret_cast<const char*>(row.data()), 2 * c);
    }
}

std::vector<float> to_mono(const Buffer& b) {
    std::vector<float> m(b.frames(), 0.0f);
    if (b.ch.empty()) return m;
    const float g = 1.0f / b.channels();
    for (const auto& c : b.ch)
        for (std::size_t i = 0; i < m.size(); ++i) m[i] += c[i] * g;
    return m;
}

std::vector<float> resample(std::span<const float> x, int from, int to) {
    if (from <= 0 || to <= 0) throw std::invalid_argument("frecuencia no válida");
    if (from == to) return {x.begin(), x.end()};
    const double ratio = static_cast<double>(to) / from;
    const std::size_t n_out = static_cast<std::size_t>(std::llround(x.size() * ratio));
    const double cutoff = std::min(1.0, ratio) * 0.95;  // fracción de Nyquist de entrada
    const int half = static_cast<int>(std::ceil(24 / cutoff));
    const double beta = 8.6, i0b = bessel_i0(beta);
    // Núcleo tabulado a 1/1024 de muestra, interpolado linealmente: error < 1e-6.
    constexpr int kOver = 1024;
    std::vector<double> table(static_cast<std::size_t>(half) * kOver + 2, 0.0);
    for (std::size_t i = 0; i < table.size(); ++i) {
        const double u = static_cast<double>(i) / kOver, r = u / half;
        if (r >= 1) break;
        const double a = std::numbers::pi * cutoff * u;
        const double sinc = a < 1e-12 ? 1.0 : std::sin(a) / a;
        table[i] = cutoff * sinc * bessel_i0(beta * std::sqrt(1 - r * r)) / i0b;
    }
    auto kernel = [&](double u) {
        u = std::abs(u) * kOver;
        const auto i = static_cast<std::size_t>(u);
        if (i + 1 >= table.size()) return 0.0;
        const double f = u - static_cast<double>(i);
        return table[i] + f * (table[i + 1] - table[i]);
    };
    std::vector<float> y(n_out);
    const long len = static_cast<long>(x.size());
    for (std::size_t j = 0; j < n_out; ++j) {
        const double t = j / ratio;
        const long c = static_cast<long>(std::floor(t));
        double acc = 0;
        for (long k = std::max(0L, c - half + 1); k <= std::min(len - 1, c + half); ++k) acc += x[k] * kernel(t - k);
        y[j] = static_cast<float>(acc);
    }
    return y;
}

}  // namespace mmn
