# MMStudio Next

Proyecto nuevo para reconstruir **MixMeister Studio 7.8** como aplicación moderna,
nativa en Apple Silicon y 100 % operativa, partiendo de su instalador.

MixMeister está en *end-of-life*: el binario es solo Intel y **macOS 27 es la
última versión con Rosetta 2 para apps Intel**. Pasado eso, no arranca.

## Documentos

- `docs/00-INSTALADOR.md` — qué hay dentro del `.pkg`, cómo se construyó y por qué no tiene futuro tal cual.
- `docs/01-MAPA-FUNCIONAL.md` — las 56 funciones del original (manual × interfaz × clases) y su estado. Es la **lista de paridad**: el proyecto está acabado cuando no quede ❌.
- `docs/02-ARQUITECTURA.md` — capas nuevas frente a las originales y hoja de ruta M0–M6.
- `engine/` — **el motor, escrito desde cero** (C++20). Estado y cifras en `engine/docs/VALIDACION.md`.
- `docs/spec/ui-nibs.md` — los 29 documentos de interfaz decodificados: ventanas, menús, atajos, ~150 acciones, outlets.
- `docs/spec/core-data.md` — modelo de datos del catálogo (5 entidades).
- `docs/spec/strings.md` — mensajes y formatos de la interfaz.

## Herramientas

- `tools/extraer.sh "MixMeister Studio.pkg" salida/` — rehace todo el inventario.
- `tools/xar_extract.py`, `tools/mom.py`, `tools/ib_summary.py` — lo que usa por dentro.
- REA + Ghidra: `../mm2027/tools/rea-setup.sh` (VM Linux x86_64).

## Relación con mm2027

`../mm2027` es trabajo previo propio: núcleo C++ de análisis, estiramiento y
mezcla, validado con números, más una app SwiftUI. Este proyecto parte de la
especificación del original y decide qué reaprovecha de ahí (ver arquitectura).

## Frontera legal

Se inspeccionan metadatos, recursos y ficheros de datos del paquete y se estudia
el comportamiento del programa (Directiva 2009/24/CE, art. 5.3), y se lee lo que
escribe para interoperar (art. 6). **No** se descompila código para copiarlo, no
se toca PACE Eden (elusión de medidas técnicas: LPI arts. 102 c) y 160, Directiva 2001/29)
y no se reutilizan marca, skins, iconos, efectos AIR ni textos del original.
