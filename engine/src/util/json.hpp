// json.hpp — JSON mínimo (valor, lectura, escritura) para la API en C. Sin dependencias.
#pragma once
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <variant>
#include <vector>

namespace mmn::json {

struct Value;
using Array = std::vector<Value>;
using Object = std::map<std::string, Value>;

struct Value {
    std::variant<std::nullptr_t, bool, double, std::string, std::shared_ptr<Array>, std::shared_ptr<Object>> v = nullptr;
    Value() = default;
    Value(std::nullptr_t) {}
    Value(bool b) : v(b) {}
    Value(double d) : v(d) {}
    Value(int i) : v(static_cast<double>(i)) {}
    Value(std::int64_t i) : v(static_cast<double>(i)) {}
    Value(std::uint32_t i) : v(static_cast<double>(i)) {}
    Value(const char* s) : v(std::string(s)) {}
    Value(std::string s) : v(std::move(s)) {}
    Value(Array a) : v(std::make_shared<Array>(std::move(a))) {}
    Value(Object o) : v(std::make_shared<Object>(std::move(o))) {}

    bool is_null() const { return std::holds_alternative<std::nullptr_t>(v); }
    bool is_object() const { return std::holds_alternative<std::shared_ptr<Object>>(v); }
    double num(double def = 0) const { return std::holds_alternative<double>(v) ? std::get<double>(v) : def; }
    bool boolean(bool def = false) const { return std::holds_alternative<bool>(v) ? std::get<bool>(v) : def; }
    std::string str(const std::string& def = {}) const { return std::holds_alternative<std::string>(v) ? std::get<std::string>(v) : def; }
    const Array& arr() const {
        static const Array empty;
        return std::holds_alternative<std::shared_ptr<Array>>(v) ? *std::get<std::shared_ptr<Array>>(v) : empty;
    }
    const Value& operator[](const std::string& k) const {
        static const Value null;
        if (!is_object()) return null;
        const auto& o = *std::get<std::shared_ptr<Object>>(v);
        const auto it = o.find(k);
        return it == o.end() ? null : it->second;
    }
    bool has(const std::string& k) const { return is_object() && std::get<std::shared_ptr<Object>>(v)->count(k); }
};

inline void escape(const std::string& s, std::string& out) {
    out += '"';
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char b[8];
                    std::snprintf(b, sizeof b, "\\u%04x", c);
                    out += b;
                } else out += static_cast<char>(c);
        }
    }
    out += '"';
}

inline void write(const Value& x, std::string& out) {
    if (x.is_null()) out += "null";
    else if (auto b = std::get_if<bool>(&x.v)) out += *b ? "true" : "false";
    else if (auto d = std::get_if<double>(&x.v)) {
        if (!std::isfinite(*d)) { out += "null"; return; }
        char buf[40];
        // %.17g conserva cualquier double; los enteros (posiciones en µs) salen sin decimales.
        if (*d == std::floor(*d) && std::fabs(*d) < 9e15) std::snprintf(buf, sizeof buf, "%.0f", *d);
        else std::snprintf(buf, sizeof buf, "%.17g", *d);
        out += buf;
    } else if (auto s = std::get_if<std::string>(&x.v)) escape(*s, out);
    else if (auto a = std::get_if<std::shared_ptr<Array>>(&x.v)) {
        out += '[';
        bool first = true;
        for (const auto& e : **a) { if (!first) out += ','; first = false; write(e, out); }
        out += ']';
    } else if (auto o = std::get_if<std::shared_ptr<Object>>(&x.v)) {
        out += '{';
        bool first = true;
        for (const auto& [k, e] : **o) { if (!first) out += ','; first = false; escape(k, out); out += ':'; write(e, out); }
        out += '}';
    }
}

inline std::string dump(const Value& x) {
    std::string s;
    write(x, s);
    return s;
}

class Parser {
public:
    explicit Parser(const std::string& s) : s_(s) {}
    Value parse() {
        Value v = value();
        ws();
        if (i_ != s_.size()) fail("texto sobrante");
        return v;
    }

private:
    const std::string& s_;
    std::size_t i_ = 0;
    [[noreturn]] void fail(const char* m) { throw std::runtime_error(std::string("JSON: ") + m + " en la posición " + std::to_string(i_)); }
    void ws() { while (i_ < s_.size() && (s_[i_] == ' ' || s_[i_] == '\n' || s_[i_] == '\r' || s_[i_] == '\t')) ++i_; }
    bool eat(char c) { ws(); if (i_ < s_.size() && s_[i_] == c) { ++i_; return true; } return false; }
    Value value() {
        ws();
        if (i_ >= s_.size()) fail("fin inesperado");
        const char c = s_[i_];
        if (c == '{') {
            ++i_;
            Object o;
            if (eat('}')) return o;
            do {
                ws();
                std::string k = string();
                if (!eat(':')) fail("falta ':'");
                o[k] = value();
            } while (eat(','));
            if (!eat('}')) fail("falta '}'");
            return o;
        }
        if (c == '[') {
            ++i_;
            Array a;
            if (eat(']')) return a;
            do a.push_back(value()); while (eat(','));
            if (!eat(']')) fail("falta ']'");
            return a;
        }
        if (c == '"') return string();
        if (s_.compare(i_, 4, "true") == 0) return i_ += 4, Value(true);
        if (s_.compare(i_, 5, "false") == 0) return i_ += 5, Value(false);
        if (s_.compare(i_, 4, "null") == 0) return i_ += 4, Value(nullptr);
        std::size_t used = 0;
        const double d = std::stod(s_.substr(i_, 40), &used);
        if (!used) fail("valor no válido");
        i_ += used;
        return d;
    }
    void utf8(std::uint32_t cp, std::string& o) {
        if (cp < 0x80) o += static_cast<char>(cp);
        else if (cp < 0x800) o += static_cast<char>(0xC0 | (cp >> 6)), o += static_cast<char>(0x80 | (cp & 0x3F));
        else if (cp < 0x10000) o += static_cast<char>(0xE0 | (cp >> 12)), o += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)), o += static_cast<char>(0x80 | (cp & 0x3F));
        else o += static_cast<char>(0xF0 | (cp >> 18)), o += static_cast<char>(0x80 | ((cp >> 12) & 0x3F)), o += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)), o += static_cast<char>(0x80 | (cp & 0x3F));
    }
    std::string string() {
        if (i_ >= s_.size() || s_[i_] != '"') fail("se esperaba una cadena");
        ++i_;
        std::string o;
        while (i_ < s_.size() && s_[i_] != '"') {
            char c = s_[i_++];
            if (c != '\\') { o += c; continue; }
            if (i_ >= s_.size()) fail("escape cortado");
            c = s_[i_++];
            switch (c) {
                case 'n': o += '\n'; break;
                case 'r': o += '\r'; break;
                case 't': o += '\t'; break;
                case 'b': o += '\b'; break;
                case 'f': o += '\f'; break;
                case 'u': {
                    auto hex = [&] { if (i_ + 4 > s_.size()) fail("\\u cortado"); auto v = static_cast<std::uint32_t>(std::stoul(s_.substr(i_, 4), nullptr, 16)); i_ += 4; return v; };
                    std::uint32_t cp = hex();
                    if (cp >= 0xD800 && cp < 0xDC00 && s_.compare(i_, 2, "\\u") == 0) { i_ += 2; cp = 0x10000 + ((cp - 0xD800) << 10) + (hex() - 0xDC00); }
                    utf8(cp, o);
                    break;
                }
                default: o += c;
            }
        }
        if (i_ >= s_.size()) fail("cadena sin cerrar");
        ++i_;
        return o;
    }
};

inline Value parse(const std::string& s) { return Parser(s).parse(); }

}  // namespace mmn::json
