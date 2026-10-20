# Motor de MMStudio Next

Motor de audio y análisis escrito desde cero en C++20. No contiene código de MixMeister
ni de mm2027. De terceros solo hay dos cabeceras: **minimp3** (CC0) para decodificar MP3
y **doctest** (MIT) para las pruebas.

## Compilar y probar (Mac o Linux)

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/mmn_tests
```

## Usar

```bash
./build/mmn analyze pista.mp3 [--json]    # tempo, primer tiempo, compás, confianza
./build/mmn mxm pista.mxm                 # lee un análisis de MixMeister
./build/mmn compare pista.mp3 pista.mxm   # el motor frente a MixMeister
./build/mmn phasediag pista.mp3 pista.mxm # rasgos para reajustar la regla de fase
sh tools/validar.sh carpeta/              # todas las parejas mp3+mxm de una carpeta
python3 tools/ajustar_fase.py rasgos.tsv  # reajusta los pesos de fase (numpy)
```

## Qué hay

| | |
|---|---|
| `include/mmn/audio.hpp` | `Buffer`, leer MP3/WAV, escribir WAV, mono, remuestreo sinc-Kaiser |
| `include/mmn/dsp.hpp` | FFT radix-2 (compleja y real), Hann, espectrograma |
| `include/mmn/analysis.hpp` | novedad espectral, candidatos de tempo, rejilla fina, compás |
| `include/mmn/mxm.hpp` | lector `.mxm` (RIFF/MXM6), con las dos variantes de contador |
| `apps/mmn.cpp` | línea de comandos |
| `tests/` | 37 comprobaciones con verdad conocida |
| `docs/MOTOR.md` | diseño |
| `docs/VALIDACION.md` | cifras medidas |

## Estado

Fase 1 del motor: **ritmo**. Demos del instalador: 11/11 en tempo, fase y compás.
Tu biblioteca (212 pistas): 97,2 % al mismo nivel métrico, mediana 0,005 BPM, 86,4 % en fase.
Lee MP3 y WAV en todas partes, y además M4A/AAC/ALAC/AIFF/FLAC en macOS. Siguiente: tonalidad, estructura y puntos de mezcla,
estiramiento temporal y mezcla, y reproducción en tiempo real.
