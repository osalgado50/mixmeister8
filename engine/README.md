# Motor de MMStudio Next

Motor de audio, análisis y mezcla escrito desde cero en C++20. No contiene código de
MixMeister, de mm2027 ni de proyectos GPL. De terceros solo hay dos cabeceras: **minimp3**
(CC0) para decodificar MP3 y **doctest** (MIT) para las pruebas. En macOS usa además
AudioToolbox (del sistema) para M4A/AAC/ALAC/AIFF/FLAC.

## Compilar y probar

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/mmn_tests          # 19 casos, 74 comprobaciones
```

## Usar

```bash
./build/mmn analyze [--json] pista.mp3            # tempo, primer tiempo, compás, confianza
./build/mmn key [--chroma] pista.mp3              # tonalidad y Camelot
./build/mmn transicion a.mp3 b.mp3 mezcla.wav     # A → B cuadradas a tiempo y compás
./build/mmn sesion lista.mmp mezcla.wav carpeta…  # sesión de MixMeister entera + .cue
./build/mmn mxm pista.mxm                         # lee un análisis de MixMeister
./build/mmn compare pista.mp3 pista.mxm           # el motor frente a MixMeister
```

Diagnóstico y reajuste (para quien quiera rehacer las reglas aprendidas con otra biblioteca):
`phasediag`, `bardiag`, `leveldiag`, `mixdiag` y los scripts de `tools/`
(`ajustar_fase.py`, `ajustar_compas.py`, `ajustar_nivel.py`, `evaluar_tonalidad.py`,
`validar.sh`).

## Qué hay

| | |
|---|---|
| `include/mmn/audio.hpp` | `Buffer`, leer audio, escribir WAV, mono, remuestreo sinc-Kaiser |
| `include/mmn/dsp.hpp` | FFT radix-2 (compleja y real), Hann, espectrograma |
| `include/mmn/analysis.hpp` | novedad espectral, tempo, nivel métrico, rejilla, fase, compás, ventanas de mezcla |
| `include/mmn/key.hpp` | cromagrama, perfiles, tonalidad, Camelot, MIREX |
| `include/mmn/stretch.hpp` | cambio de tempo sin cambio de tono (WSOLA) guiado por un mapa de tiempos |
| `include/mmn/mix.hpp` | transición y sesión de N pistas, con limitador |
| `include/mmn/mxm.hpp`, `mmp.hpp` | lectura de los formatos de MixMeister |
| `apps/mmn.cpp` | línea de comandos |
| `tests/` | pruebas con verdad conocida |
| `docs/MOTOR.md`, `docs/VALIDACION.md` | diseño y cifras medidas |
| `validacion/` | resultados por pista contra la biblioteca real y GiantSteps |

## Reglas aprendidas, no impuestas

Fase, compás y nivel métrico se deciden con regresiones pequeñas (3 a 8 rasgos con nombre)
ajustadas con lo que MixMeister guardó en 178-212 pistas reales, y medidas en pistas que no
entraron en el ajuste. Los perfiles de tonalidad se aprendieron de las 604 pistas anotadas
de GiantSteps. Cada regla lleva en el código su procedencia, su acierto y cómo rehacerla.
