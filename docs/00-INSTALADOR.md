# El instalador de MixMeister Studio 7.8, abierto

Fuente: `MixMeister Studio.pkg` (143,6 MB). Extraído con `tools/xar_extract.py` +
`gzip | cpio`; nibs con REA 6.7 (`decode-interface-builder`); binario inventariado
con REA + Ghidra 12.1.4. Todo reproducible con `tools/extraer.sh`.

## El paquete

| Dato | Valor |
|---|---|
| Formato | xar «flat package», hecho con *Packages* 1.2.10 |
| Componentes | uno: `com.mixmeister.pkg.MixMeisterStudio` v7.8, instala en `/` como root |
| Arquitectura exigida | `hostArchitectures="x86_64"` |
| Tamaño instalado | 297 136 582 bytes, 150 ficheros (204 entradas con carpetas) |
| Scripts pre/postinstall | **ninguno** (el archivo `Scripts` es un cpio vacío) |
| Binario principal | idéntico al `.app` que ya tienes (SHA-256 `f0dffccf4d9fae16…`) |

Instalar no hace nada más que copiar `MixMeister Studio.app` a `/Applications`.
Lo que el programa necesita (carpeta `Library/Application Support/MixMeister`,
catálogo Core Data) lo crea él al arrancar.

## Qué lleva dentro

| Bloque | Peso | Qué es |
|---|---|---|
| 7 efectos VST2 «AIR» (Delay, Distortion, Filter Gate, Flanger, Fuzz-Wah, Non-Lin Reverb, Phaser) | 246,2 MB · **82,9 %** | Plug-ins de inMusic/AIR, binarios universales x86_64+arm64. Licenciados, no se reutilizan |
| Binario `MixMeister Studio` | 7,2 MB | Mach-O **solo x86_64**. 2 793 funciones, 5 663 cadenas, 121 clases Objective-C, C++ (libc++) |
| PACE Eden 5.8.1 | ~0,5 MB | `__Pace_Eden.bundle`, `PlugIns/__Pace_Eden/libWrapHelper.dylib`, `wraptool.winfo`, pantallas de activación. **Fuera de alcance** |
| Skins | 15,5 MB | `skin`, `skinactive`, `skindisabled`, `skindown`, `skinhover` (BMP 3,1 MB c/u), `knobstrip`, 4 juegos de controladora (*mixmeister/omni/stealth/total control*) |
| 11 MP3 de demostración + `sample playlist.mmp` | 14,5 MB | Corpus de prueba ya usado por mm2027 |
| Interfaz | 30 nibs (26 diálogos + MainMenu en 3 variantes) | Ver `spec/ui-nibs.md` |
| Datos | | `FactoryDefaults.plist`, `MmCatalog.mom`, `transitions.xml` (13 transiciones), `miditemplates.xml`, `MetHigh/MetLow.wav` (metrónomo), `watermark.raw` (marca de la demo) |
| Manual | 132 p. | `MMFusionForMac.pdf` — es el de **Fusion** (2009): Studio y Fusion son el mismo código con distinto icono, splash y límites |

## Cómo se construyó (Info.plist)

Xcode 13.1, SDK macOS 12.0, máquina de compilación macOS 12.4 (21F79), mínimo
macOS 10.11. `NSRequiresAquaSystemAppearance = YES`: no admite modo oscuro.
Un solo tipo de documento: `.mmp` («MixMeister Playlist», rol Editor).

## Por qué no tiene futuro tal cual

Enlaza 23 librerías. Las que lo condenan:

| Dependencia | Problema | Sustituto en el proyecto nuevo |
|---|---|---|
| Binario solo x86_64 | Vive de Rosetta 2, y **macOS 27 es la última versión con Rosetta para apps Intel** | Compilación nativa arm64 (+x86_64 opcional) |
| `QTKit` | API retirada hace años | `AVFoundation` |
| `Carbon` | API heredada | AppKit / SwiftUI |
| `ScriptingBridge` (iTunes) | iTunes ya no existe | Importar de Apple Music (XML) y de rekordbox |
| VST2 | Steinberg retiró el SDK de VST2 | AUv3 (y efectos propios) |
| `DiscRecording` | Grabar CD de audio: residual | Prioridad baja |
| PACE Eden | DRM ligado a un servicio que ya no vende | Ninguno: el proyecto nuevo es tuyo |

## Lo que se hizo y lo que no

Se leyeron metadatos, recursos y ficheros de datos del paquete (nibs, plists,
modelo Core Data, cadenas, manual) y la tabla de clases y librerías del binario.
**No** se descompiló código ni se tocó nada de PACE. Ver «Frontera legal» en el
README.
