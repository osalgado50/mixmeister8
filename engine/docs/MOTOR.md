# Motor MMStudio Next — diseño

Motor escrito desde cero, en C++20, sin código de MixMeister ni de mm2027.
Dependencias de terceros, solo dos y en cabecera: **minimp3** (CC0, decodificar
MP3) y **doctest** (MIT, pruebas). FFT, remuestreo, análisis y mezcla son propios.

## Módulos

| Módulo | Qué hace | Contrato |
|---|---|---|
| `audio` | `Buffer` (planar, float32), leer MP3/WAV, escribir WAV, mono | Lee a la frecuencia nativa; nunca cambia la longitud sin decirlo |
| `dsp` | FFT real/compleja radix-2, ventanas, STFT, remuestreo sinc enventanado | FFT exacta a 1e-5 contra DFT directa |
| `analysis/onset` | Envolvente de novedad: flujo espectral log-comprimido en bandas | Una muestra cada `hop` (≈5,8 ms) |
| `analysis/tempo` | Tempo global: autocorrelación + peine armónico con prior de DJ | Devuelve candidatos con puntuación, no solo uno |
| `analysis/grid` | Rejilla de tempo constante: periodo y fase finos por coherencia de fase | Error de BPM < 0,01 en material de tempo fijo |
| `analysis/downbeat` | Primer tiempo del compás (fase 0-3) | |
| `formats/mxm` | Lector de `.mxm` de MixMeister (interoperabilidad) | Detecta las dos variantes de contador |
| CLI `mmn` | `analyze`, `mxm`, `compare` | Salida legible y `--json` |

## Por qué rejilla constante primero

La música de baile que MixMeister mezclaba es de tempo fijo; el original guarda
**un** BPM por pista con cuatro decimales (128,0008). La forma de llegar a esa
precisión no es contar beats sueltos, sino buscar el periodo y la fase que
maximizan la energía de ataque bajo una rejilla rígida a lo largo de toda la
pista: cuantos más compases, más fino el periodo. El seguimiento de tempo
variable vendrá después, como refinamiento por tramos.

## Validación

- **Sintética**: clics a BPM conocido (con ruido, desfase y swing) → error de BPM y de fase.
- **Contra MixMeister**: las 11 demos con su `.mxm`, y la biblioteca real (212) cuando haya acceso al audio.
- Métrica principal: |ΔBPM| y acierto de **nivel métrico** (no confundir 64 con 128).
