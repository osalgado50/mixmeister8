# MMStudio Next

Reconstrucción moderna de **MixMeister Studio 7.8**: nativa en macOS (Intel y Apple
Silicon), con un motor de análisis y mezcla escrito desde cero y validado contra lo que el
propio MixMeister dejó en tu biblioteca.

MixMeister está en *end-of-life*: el binario es solo Intel y **macOS 27 es la última versión
con Rosetta 2 para apps Intel**.

## Estado

| Pieza | Estado | Medido contra |
|---|---|---|
| Lectura de audio | MP3, WAV; en macOS también M4A/AAC/ALAC/AIFF/FLAC | — |
| Tempo | **98,6 %** al mismo nivel métrico, mediana **0,005 BPM** | 212 pistas con su `.mxm` |
| Fase (dónde cae el tiempo) | **86 %** | ídem |
| Compás | **79 %** | ídem |
| Tonalidad + Camelot | MIREX **0,652** | 604 pistas de GiantSteps Key |
| Ventanas de mezcla (8 compases) | entrada 60 % exacta / 88 % ±1 compás; salida 77 % | 195 pistas con su `.mxm` |
| Cambio de tempo sin cambiar el tono | WSOLA; tono < 1 Hz de error a ±12 % | pruebas sintéticas |
| Transición entre dos pistas | rampa de tempo, golpes cuadrados, sin saturar | pruebas + escucha |
| Sesiones `.mmp` de MixMeister | se leen, se encuentra el audio, se renderizan con `.cue` | lista de muestra del instalador |
| Reproducción en directo, interfaz | pendiente | — |

Cifras completas y método: `engine/docs/VALIDACION.md`.

## Estructura

- `engine/` — el motor (C++20, sin dependencias salvo dos cabeceras: minimp3 y doctest).
- `docs/00-INSTALADOR.md` — qué hay dentro del `.pkg` de MixMeister y por qué no tiene futuro tal cual.
- `docs/01-MAPA-FUNCIONAL.md` — las 56 funciones del original y su estado: la lista de paridad.
- `docs/02-ARQUITECTURA.md` — capas nuevas frente a las originales y hoja de ruta.
- `docs/spec/` — interfaz (29 nibs), modelo de datos y cadenas del original, decodificados.
- `tools/` — extracción del instalador (`extraer.sh` y auxiliares).

## Compilar y probar (en el Mac, Terminal)

```bash
cd engine
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/mmn_tests
```

## Usar

```bash
./build/mmn analyze pista.mp3                  # tempo, fase, compás
./build/mmn key pista.mp3                      # tonalidad y Camelot
./build/mmn transicion a.mp3 b.mp3 mezcla.wav  # A → B cuadradas
./build/mmn sesion lista.mmp mezcla.wav ~/Music   # una sesión de MixMeister entera (+ .cue)
```

## Frontera legal

Se leen metadatos, recursos y ficheros de datos del original y se estudia su comportamiento
(Directiva 2009/24/CE, art. 5.3), y se leen sus formatos para interoperar (art. 6). No se
descompila código para copiarlo, no se toca PACE Eden y no se reutilizan marca, skins,
iconos, efectos ni textos del original. El motor no contiene código de MixMeister, de mm2027
ni de proyectos GPL.
