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
| 2. Reproducción | Play/Pause, Stop, Jog, Previous/Next, Mix Now, preescucha, medidores, salida elegible (Audio Output Configuration), volumen/EQ/tono/tempo por marcadores, rampas de tempo dentro de cada pista, limitador del master | **hecho**, probado en el Mac Pro (7 pasos de transporte); pendiente: arrastre de tempo en transiciones beatmix, segmentos invertidos |
| 3. Edición de la línea de tiempo | arrastrar pistas y anclas, marcadores de volumen/EQ/etiqueta/bucle/efecto (añadir, mover, editar, borrar), Split, Reverse, Solo, overlays, tempo markers en la regla, Snap | |
| 4. Diálogos | Edit Tag (tap, ½×, 2×, tonalidad), Track Settings, Tweaks y Quick Save, Smart Playlist, Find Similar, categorías, Clean Up/Import/Export Library, Add Files (análisis con el motor), Preferences | |
| 5. Song Slicer y efectos | Beat Slicer con metrónomo; Effects Rack con efectos propios equivalentes a los del original (los AIR/NewBlue no se pueden incluir); parámetros automatizados | **hecho** (ver abajo); falta: efecto en parte de una pista, Save as Tweak, nombres de parámetros de los AIR |
| 6. Directo y salida | salida doble (principal y preescucha), Perform/Pause, Fade and Cue Next, Mix Performance Now, Push/Drag Tempo, MIDI Learn y plantillas, MIDI clock | |
| 7. Exportar | a fichero (AIFF/WAV/AAC, por canciones o por etiquetas), a Música (iTunes), CD de audio sin pausas (CUE/BIN + grabadora del sistema), botones de arriba a la derecha de la lista; imprimir biblioteca y lista | **hecho** salvo MP3 (macOS no trae codificador) e imprimir; la grabación física del CD falta probarla con una grabadora conectada |

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

## Tempo (barra de tempos y Master BPM)

- Barra de tempos bajo los carriles: marcadores de tempo (verde) y de tempo original (verde apagado);
  clic derecho: Add Tempo Marker / Add Original Tempo Marker; sobre un marcador: Edit / Delete; doble
  clic: editar el valor.
- Master BPM: el tempo en el cursor; flechas (0,1 BPM) o tecleado: deja marcadores de tempo en el cursor.
- Columna BPM de la lista: tempo a mitad de la pista. Spinning310: 19 de 21 filas iguales a MixMeister
  7.8 (las filas 13 y 21 dependen del arrastre de tempo en las transiciones beatmix).

## Efectos (Effects Rack) — comprobado en el Mac Pro

- Lista de efectos (pestaña Effects de la biblioteca, View › Effects): «Nombre - Fabricante», como el
  original. 15 efectos propios —los 7 del original con su función (Distortion, Non-Lin Reverb, Delay,
  Fuzz-Wah, Flanger, Filter Gate, Phaser) y Reverb, Parametric EQ, Stereoizer, MultiLimit, Limiter,
  Compressor, Low-Pass, High-Pass— más todos los Audio Units de efectos instalados en el Mac (35 en el
  Mac Pro: FabFilter, iZotope…), igual que el original admitía VST de otros fabricantes.
- Se arrastran a una pista (efecto de la pista), al fondo de la línea de tiempo (master) o al rack;
  doble clic: a la pista seleccionada.
- Rack: a la izquierda Master Output o la pista, el desplegable de efectos, el de parámetros
  (Enable/Bypass y los parámetros) y Clear Automation on this parameter / for this effect / Show the
  Effect Control Panel (la interfaz del Audio Unit). A la derecha un módulo por efecto: Enable/Bypass,
  nombre y knobs (arrastrar; ⇧ fino; doble clic = valor por defecto). Supr o clic derecho › Delete.
- Automatización: con la mezcla sonando, mover el knob del parámetro elegido graba marcadores
  0x08000000 (flag = instancia << 12 | parámetro; 0xFFF = Enable/Bypass) y se ven en la pista (cian).
- Formato (EFXT): plugin_id = código de 4 letras (los propios «M8xx»), slot = número de instancia,
  flags bit 0 = desactivado, parámetros normalizados. Los efectos del original se conservan intactos y
  suenan con su equivalente propio (MultiLimit → Limiter).
- Pruebas: los 15 cargan; exportación con cada uno distinta de la seca (correlación 0,62–0,99) y
  Flanger a 0 idéntica a la seca; lista guardada = original + 86 bytes del EFXT; MixMeister 7.8 abre
  esa lista (el efecto propio lo deja sin cargar, sin error).

## Song Slicer — comprobado contra MixMeister 7.8

- Rejilla entre marcadores de compás (TKTM): entre dos marcadores, round(distancia/compás) compases
  iguales; regla «compás:0» en cada marcador (Spinning310 pista 2: 0, 7, 9, 16, 20, 23, 28, 31, 50,
  53, 61, 78 — igual que el original).
- BPM original (insignia): arrastrar o **doble clic para escribirlo**. Cambia TKTH, el BPM de la pista y
  sus marcadores de tempo original; con compás ×2 quedan los marcadores de compás par (de 101,96 a 50:
  8:0, 10:0, 14:0, 25:0, como el original; el original quita también el último, MM8 lo deja).
- Flechas blancas: mover la rejilla; primera/última línea: estirar o comprimir; mover un marcador
  suelto; Add Measure Start Marker, Delete All Measure Markers, Restore default (análisis),
  preescucha con metrónomo (clics propios). Save as Tweak: pendiente (Tweaks).

## Tempo del audio frente a tempo de la mezcla (corregido)

- La velocidad de una pista es tempo de la mezcla / tempo del audio (TRKH). El marcador de tempo
  original es el tempo al que suena en la mezcla. Con esto Spinning310 dura 47:33 (original 47:34; antes
  47:04). Doble clic en un BPM de la barra de tempos: se escribe ahí mismo.

## Pendiente de averiguar (por experimento)

- Cuándo MixMeister rotula una transición como «Simple Custom» o «Beatmix Custom» (la lista guarda
  «No Transition» o «Beatmix 8»).
- Orden de reproducción de los segmentos reordenados a mano (Spinning310, pista 3).
- Tonalidades mayores en el catálogo (todas las de la biblioteca actual son menores).
- Nombres y orden de los parámetros de los AIR (para mapear sus valores al equivalente propio).
- Efecto aplicado a una parte de la pista (arrastrar sobre un tramo resaltado).

## Compilar (en el Mac, Terminal)

```bash
cd ~/dev/mm8/mmstudio-next
swift build -c release && app/bundle.sh
open "build/MixMeister 8.app"
```
