// Ida y vuelta por la API en C: abrir → JSON → reconstruir desde el JSON → guardar = original.
#include "mmn_c.h"
#include "mmn/mmp.hpp"
#include <cstdio>
int main(int argc, char** argv) {
    int ok = 0, bad = 0;
    for (int i = 1; i < argc; ++i) {
        char* err = nullptr;
        mmn_playlist* p = mmn_playlist_open(argv[i], &err);
        if (!p) { std::printf("ERROR %s %s\n", argv[i], err); mmn_free_string(err); ++bad; continue; }
        const std::string js = mmn_playlist_json(p);
        mmn_playlist* q = mmn_playlist_open(argv[i], nullptr);
        if (mmn_playlist_set_json(q, js.c_str(), &err)) { std::printf("JSON %s %s\n", argv[i], err); ++bad; continue; }
        mmn_playlist_save(q, "/tmp/capi_check.mmp", nullptr);
        if (mmn::read_file(argv[i]) == mmn::read_file("/tmp/capi_check.mmp")) ++ok; else { std::printf("DIFIERE %s\n", argv[i]); ++bad; }
        mmn_playlist_free(p); mmn_playlist_free(q);
    }
    std::printf("idénticas %d de %d\n", ok, ok + bad);
    return bad != 0;
}
