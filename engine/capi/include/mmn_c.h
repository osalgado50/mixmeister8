/* mmn_c.h — API en C del motor de MixMeister 8, para la app (Swift) y cualquier otro cliente.
 *
 * Reglas: las cadenas son UTF-8. Lo que devuelve `const char*` pertenece al objeto que lo da y
 * vale hasta la siguiente llamada sobre ese objeto o hasta liberarlo. Los errores se devuelven en
 * `err` (puede ser NULL) como texto que hay que liberar con mmn_free_string.
 */
#ifndef MMN_C_H
#define MMN_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void mmn_free_string(char* s);
const char* mmn_version(void);

/* ---------- Listas .mmp ---------------------------------------------------------------------- */

typedef struct mmn_playlist mmn_playlist;

mmn_playlist* mmn_playlist_new(void);
mmn_playlist* mmn_playlist_open(const char* path, char** err);
void mmn_playlist_free(mmn_playlist* p);
/* Toda la lista en JSON (pistas, segmentos, marcadores, efectos). */
const char* mmn_playlist_json(mmn_playlist* p);
/* Sustituye la lista por la descrita en JSON (mismo esquema que mmn_playlist_json). Lo que el JSON
 * no describe (bytes sin interpretar) se conserva de la lista anterior, pista a pista. */
int mmn_playlist_set_json(mmn_playlist* p, const char* json, char** err);
int mmn_playlist_save(mmn_playlist* p, const char* path, char** err);

/* ---------- Audio ---------------------------------------------------------------------------- */

/* Envolvente para dibujar la forma de onda: `bins` máximos absolutos (0..1), mono.
 * Devuelve la duración en segundos, o < 0 si no se pudo leer. */
double mmn_audio_peaks(const char* path, float* out, size_t bins, char** err);

/* Análisis de una pista (tempo, rejilla, tonalidad) en JSON. Liberar con mmn_free_string. */
char* mmn_analyze_json(const char* path, char** err);

/* ---------- Efectos propios (sustituyen a los AIR/NewBlue del original) ----------------------- */

#define MMN_FX_FLANGER 1     /* rate, depth, feedback, mix */
#define MMN_FX_PHASER 2      /* rate, depth, feedback, stages, mix */
#define MMN_FX_FUZZWAH 3     /* drive, wah freq, resonance, lfo rate, lfo depth, mix */
#define MMN_FX_FILTERGATE 4  /* cutoff, resonance, type (LP/BP/HP), gate rate, gate depth, mix */
#define MMN_FX_STEREOIZER 5  /* width, haas, mix */

typedef struct mmn_fx mmn_fx;
int mmn_fx_param_count(int kind);
float mmn_fx_param_default(int kind, int param);
mmn_fx* mmn_fx_new(int kind, double sample_rate, int channels);
void mmn_fx_free(mmn_fx* fx);
/* Parámetros normalizados 0..1. Se pueden cambiar desde otro hilo mientras se procesa. */
void mmn_fx_set(mmn_fx* fx, int param, float value);
float mmn_fx_get(mmn_fx* fx, int param);
void mmn_fx_reset(mmn_fx* fx);
/* Procesa en el sitio; `right` puede ser NULL (mono). */
void mmn_fx_process(mmn_fx* fx, float* left, float* right, int frames);

#ifdef __cplusplus
}
#endif
#endif
