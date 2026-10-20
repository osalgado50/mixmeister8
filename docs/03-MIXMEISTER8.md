# MixMeister 8 — plan de paridad y estado

Objetivo: continuar MixMeister. Misma operativa que **MixMeister Fusion 7.8**, todos sus menús y
funciones, imagen renovada, versión 8, nativa en macOS actual (Intel y Apple Silicon), y que
cualquier fichero de MixMeister (listas `.mmp`, análisis `.mxm`, la biblioteca) se abra y funcione
igual. Uso propio: si algún día se distribuye, necesita otro nombre (la marca es de inMusic).

Cómo se hace: se copia la **operativa** (menús, diálogos, comportamiento observado, formatos), no
el código. Fusion y Studio 7.8 son el mismo programa (mismos 29 nibs; Studio desactiva partes),
así que la especificación sale de los nibs de Fusion (`spec/menus-fusion.md`, `spec/ui-nibs.md`),
de su manual (120 págs.) y de experimentos en MixMeister Studio 7.8 instalado en el Mac Pro.

## Fases

| Fase | Contenido | Estado |
|---|---|---|
| **0. Formatos** | `.mmp` lectura/escritura sin pérdidas; catálogo; `.mxm`; preferencias | **hecho**: 652/652 listas idénticas al byte, también pasando por la API |
| **1. Esqueleto** | menús exactos (generados del nib), ventana con biblioteca/lista/línea de tiempo/rack, biblioteca desde el catálogo de MixMeister, abrir/guardar/añadir listas, recientes, columnas y anchuras heredadas, carriles 2/4/6/8, zoom, regla, Snap To, transiciones por pista, deshacer | **hecho** (ver abajo) |
| 2. Reproducción | motor en tiempo real (AVAudioEngine + motor C++): Play/Pause, Stop, Jog, Previous/Next, cursor, medidores; mapa de tempo con rampas (BPM de la lista exacto); las 13 transiciones aplicadas | siguiente |
| 3. Edición de la línea de tiempo | arrastrar pistas y anclas, marcadores de volumen/EQ/etiqueta/bucle/efecto (añadir, mover, editar, borrar), Split, Reverse, Solo, overlays, tempo markers en la regla, Snap | |
| 4. Diálogos | Edit Tag (tap, ½×, 2×, tonalidad), Track Settings, Tweaks y Quick Save, Smart Playlist, Find Similar, categorías, Clean Up/Import/Export Library, Add Files (análisis con el motor), Preferences | |
| 5. Song Slicer y efectos | Beat Slicer con metrónomo; Effects Rack con efectos propios equivalentes a los del original (los AIR/NewBlue no se pueden incluir); parámetros automatizados | |
| 6. Directo y salida | salida doble (principal y preescucha), Perform/Pause, Fade and Cue Next, Mix Performance Now, Push/Drag Tempo, MIDI Learn y plantillas, MIDI clock | |
| 7. Exportar | a fichero (WAV/AIFF/MP3/AAC, por canciones o por etiquetas), CD, Mobile Mix, imprimir biblioteca y lista | |

## Fase 1 — lo que ya hace la app

- **Menús**: los 12 menús y 10 contextuales del nib, con títulos, orden, separadores, atajos
  (F6, F10–F12, ⌃G, ⌃W, V/T/M/B…) y selectores originales. Cambios: el nombre «MixMeister 8» y fuera
  «Buy Now…» y «Register Online…». Lo que aún no está implementado sale desactivado.
- **Biblioteca**: lee la biblioteca de MixMeister (copia, nunca el original), con búsqueda,
  categorías, orden, KEY y KEYCODE (círculo de quintas desde La menor = ①, comprobado con la
  biblioteca real) y las columnas visibles y anchuras que tenías en MixMeister.
- **Lista**: abrir, añadir (Append), guardar y guardar como, en formato `.mmp` que MixMeister 7
  vuelve a abrir. Encuentra el audio aunque la ruta sea de otro ordenador (Windows, otro disco):
  identificador del fichero en la biblioteca, mismo nombre junto a la lista, nombre en la
  biblioteca. Las pistas sin audio se ven en rojo.
- **Línea de tiempo**: pistas colocadas como en MixMeister (el ancla de entrada sobre el ancla de
  salida de la anterior), formas de onda, segmentos, envolventes de volumen y EQ, tempo, etiquetas,
  bucles y anclas; regla en compases o tiempo; 2/4/6/8 carriles; zoom; CURRENT/REMAINING/TOTAL.
- **Comprobado con Spinning310** (24 pistas) frente a MixMeister 7.8: tonalidades iguales, BPM igual
  en 19 de 21 filas visibles, disposición igual, duración total 47:06 frente a 47:34. Lo que
  falta en las dos últimas cifras son las rampas de tempo (fase 2).

## Pendiente de averiguar (por experimento)

- Cuándo MixMeister rotula una transición como «Simple Custom» o «Beatmix Custom» (la lista guarda
  «No Transition» o «Beatmix 8»).
- Orden de reproducción de los segmentos reordenados a mano (Spinning310, pista 3).
- Tonalidades mayores en el catálogo (todas las de la biblioteca actual son menores).
- Comprobar que MixMeister 7.8 abre una lista escrita por MixMeister 8 (preparada:
  `SWAT DJ's/_mm8exp/mm8-escrito.mmp`; necesita la pantalla del Mac desbloqueada).

## Compilar (en el Mac, Terminal)

```bash
cd ~/dev/mm8/mmstudio-next
swift build -c release && app/bundle.sh
open "build/MixMeister 8.app"
```
