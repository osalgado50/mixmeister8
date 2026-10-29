# Mapa funcional — qué hace MixMeister Studio y qué hay que construir

Cada función sale de tres fuentes cruzadas: el **manual** (capítulo), la
**interfaz** (menú / selector de acción en los nibs, `spec/ui-nibs.md`) y las
**clases** del binario. La última columna dice dónde está hoy en `mm2027`, el
trabajo previo propio que puede servir de motor.


## Estado en el motor nuevo (`engine/`) — 20-10-2026

El motor nuevo se escribe desde cero (decisión del 20-10-2026) y no reutiliza mm2027. La
columna «mm2027» de las tablas de abajo queda como referencia histórica; lo que ya cubre el
motor nuevo, medido:

| Función del original | Motor nuevo |
|---|---|
| Análisis BPM / rejilla / compás | ✅ 98,6 % nivel, 86 % fase, 79 % compás (212 pistas) |
| Tonalidad y keycode | ✅ MIREX 0,652 (GiantSteps), notación Camelot |
| Anclas de intro / outro (ventanas de mezcla) | ✅ frases de 8 compases, como MixMeister |
| Mezcla por defecto: transición cuadrada con rampa de tempo | ✅ cruce a potencia constante (falta el resto de los 13 tipos de `transitions.xml`) |
| Cambio de tempo sin cambio de tono | ✅ WSOLA |
| Abrir sesiones `.mmp` | ✅ lectura; escribir `.mmp` pendiente |
| Localizar ficheros perdidos | ✅ por nombre en las carpetas indicadas |
| Exportar la mezcla a WAV con CUE | ✅ |
| Leer M4A/AAC | ✅ en macOS |
| Reproducción en directo, interfaz, efectos, MIDI, categorías | pendiente |

Leyenda: ✅ hecho en mm2027 · 🟡 parcial · ❌ falta · ⛔ no se replica

## 1. Biblioteca

| Función | Acción en la interfaz | Clase original | mm2027 |
|---|---|---|---|
| Añadir ficheros / carpetas | `addFilesToLibrary:` (AddMusicFilesToLibraryDlg) | AddMusicFilesController, MmLibrary | 🟡 lee el catálogo existente y analiza |
| Análisis BPM, rejilla, tonalidad, estructura | cola `ProfileWorkItem` | MmEngineManager, CProfileBuilder | ✅ validado: 98,0 % nivel, 89,5 % fase, 87,2 % compás frente a MixMeister (4175 pistas) |
| Columnas elegibles (21) y orden | `toggleTitle:` … `toggleUser2:` | CatalogDataSource | ✅ |
| Buscar | `searchTextDidChange:` | LibraryController | ✅ |
| Escuchar en la biblioteca | `catPreviewPlay:` / `catPreviewStop:` | LibraryController | 🟡 suena la pista seleccionada |
| Categorías: crear, borrar, añadir, quitar | `newCategory:` `deleteCategory:` `addToCategory:` `removeFromActiveCategory:` | CategoryDataSource, AddCategoryController | ❌ |
| Listas inteligentes | `smartPlaylist:` (SmartPlaylist.nib) | SmartPlaylistController | ❌ |
| Editar etiquetas | `editTag:` (EditTagDlg, 31 KB: el diálogo más grande) | EditTagController | ❌ |
| Buscar parecidas / keycodes | `findSimilarTracks:` | — | ✅ `siguiente` |
| Importar de iTunes | `importITunes:` | ImportITunesController, iTunesController | ❌ → Apple Music XML |
| Importar / exportar biblioteca (.txt) | `importLibrary:` `exportLibrary:` | CatImporter | ❌ (exporta a rekordbox ✅) |
| Limpiar biblioteca / localizar ficheros perdidos | `cleanUpLibrary:` (FindFileErrorDlg) | FindFileErrorController | 🟡 `mm-reparar.sh` |
| Imprimir biblioteca / lista | `printLibrary:` `printPlaylist:` | — | ❌ |

## 2. Lista de reproducción (mezcla)

| Función | Acción | Clase | mm2027 |
|---|---|---|---|
| Nueva / abrir / añadir / recientes | `newPlayList:` `openPlayList:` `appendPlayList:` | PlaylistController | 🟡 lee `.mmp` |
| Guardar `.mmp` | `savePlayList:` `savePlayListAs:` | MmPlaylist | 🟡 guarda en formato propio (JSON); escribir `.mmp` no |
| Transición por pista (13 tipos de `transitions.xml`, incl. Pause, Beatmix/Simple Custom) | columna TRANSITION | TransitionComboDataSource | 🟡 verificar que están las 13 |
| Ajustes de pista (tempo, tono, ganancia) | `adjustTrackSettings:` (TrackSettings.nib) | AdjustTrackSettingsController | 🟡 |
| *Tweaks* y *Quick Save Tweak* (presets por pista) | `tweaks:` `quickSaveTweak:` `trackPresets:` | TweaksController, entidad TrackPreset | ❌ |
| Mezcla por defecto | Preferencias | MontagePreset | 🟡 |

## 3. Línea de tiempo

| Función | Acción | Clase | mm2027 |
|---|---|---|---|
| 2 / 4 / 6 / 8 carriles, zoom, regla tiempo o compases | `view2Strips:`… `zoomIn:` `timelineRulerMeasuresAndBeats:` | MmTimeline, MmRuler | ✅ |
| Mover solape arrastrando | asas de segmento | MmTimelineTrack | ✅ |
| Encaje a beat, ½, ¼, ⅛, 1⁄16, 1/2/4/8 compases | `snapToBeat:` … `snapTo8Measures:` | — | 🟡 solo a compás |
| Anclas de intro / outro | IDS_TOOLTIP_INTROSPROC/OUTROSPROC | — | ✅ ventanas de mezcla |
| Automatización volumen / agudos / medios / graves con varios puntos | `addVolumeMarker:` `addTrebleMarker:` `addMidrangeMarker:` `addBassMarker:` | MmTrackCtrlView | ❌ hoy un nivel por pista |
| Marcadores de parámetro de efecto | `addEffectsParameterMarker:` | MmEfxCtrlMod | ❌ |
| Bucles 1/2/4/8 | botones de carril | — | ✅ |
| Marcadores libres de inicio / fin de bucle | `addLoopStartMarker:` `addLoopEndMarker:` | — | ❌ |
| Partir segmento, recortar / alargar | `splitSegmentAtCursor:` | — | ❌ |
| Invertir (reproducir al revés) | `reverse:` | — | ❌ |
| Solo de pista | botón Solo | — | ❌ |
| Marcadores de tempo, tempo original, arrastrar tempo | `rulerAddTempoMarker:` `dragTempo:` `pushTempo:` | — | ❌ (curva automática ✅) |
| Cambiar tonalidad | TrackSettings | — | ❌ |
| Pistas superpuestas (*overlay*) sincronizadas | manual cap. «Primary and Overlay tracks» | — | ❌ |
| Etiquetas en la línea | `addLabelMarker:` | MmRulerLabel | ❌ |
| Deshacer / rehacer | `undo:` `redo:` | — | 🟡 |

## 4. Beat Slicer (Song Slicer)

| Función | Acción | mm2027 |
|---|---|---|
| Ver rejilla, frases, ventanas | `viewSongSlicer:` | ✅ |
| Corregir fase, tempo, ÷2 ×2, compás, metrónomo | `addMeasureStartMarker:` `deleteAllMeasureMarkers:` | ✅ |

## 5. Efectos

| Función | Acción | Clase | mm2027 |
|---|---|---|---|
| Rack de efectos por pista y en el master | `viewEffectsRack:` | MmEffectsRackView, MmEfxCtrl | ❌ → AUv3 |
| Lista de efectos disponibles | `viewEffects:` | MmEffectsList, EfxPluginDataSource | ❌ |
| Compresor / normalizar volumen entre pistas | manual cap. «compressor» | — | ❌ |
| Efectos de sonido | — | MmSoundEffectsController | ❌ |

## 6. Salidas

| Función | Acción | mm2027 |
|---|---|---|
| Exportar a fichero (WAV) con CUE y M3U | `exportPlaylistToFile:` (SavePlaylistAudio.nib) | ✅ |
| Exportar a MP3 / AAC | idem, «File Format» | ❌ |
| Exportar a iTunes / *Mobile Mix* / dispositivo | `exportPlaylistToDevice:` `exportPlaylistAsMobileMix:` | ⛔ obsoleto → «Compartir» |
| Grabar CD | `burnCD:` (CdBurnerDlg) | ❌ baja prioridad |

## 7. Directo

| Función | Acción | Clase | mm2027 |
|---|---|---|---|
| Reproducir la mezcla en vivo | `playPause:` `stop:` | MmEngineManager | ✅ |
| Doble salida: master + auriculares | StudioOutputConfigurationDlg, OutputConfigurationDlg | — | ❌ |
| *Mix Now*, parar y preparar la siguiente, fijar siguiente | `mixNow:` `mixPerformanceNow:` `stopAndCueNext:` `setAsNextPerformanceTrack:` | — | ❌ |
| Avance / retroceso, pista anterior / siguiente | `jogForward:` `jogBackward:` `nextTrack:` `previousTrack:` | — | 🟡 |
| Mostrar pistas ya pinchadas | `showPerformedTracks:` | — | ❌ |
| Controladoras MIDI y *MIDI learn* (`miditemplates.xml`) | PrefMidiController | MIDIConfigurationController | ❌ |
| Vúmetro, volumen y EQ de 3 bandas por pista | — | MmVuMeter | ✅ |

## 8. Sistema

| Función | mm2027 |
|---|---|
| Preferencias: Biblioteca, MIDI, Ficheros de música, Lista, *Plot files* | 🟡 |
| Modo oscuro, Retina, Apple Silicon | ✅ |
| Registro, «Buy Now», comprobar actualizaciones, PACE, marca de agua demo | ⛔ |

## Recuento

| | ✅ | 🟡 | ❌ | ⛔ |
|---|---|---|---|---|
| Funciones (56) | 14 | 12 | 27 | 3 |

Lo grueso que falta, por orden de impacto para un DJ: **automatización con
varios puntos**, **segmentos (partir / recortar / invertir / solo)**,
**directo con doble salida y Mix Now**, **efectos AUv3**, **categorías y listas
inteligentes**, **exportar a MP3/AAC**, **MIDI**.
