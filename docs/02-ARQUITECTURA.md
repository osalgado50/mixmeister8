# Arquitectura propuesta y hoja de ruta

Nombre de trabajo: **MMStudio Next**. «MixMeister» es marca de inMusic: sirve
para uso propio, no para publicar.

## Capas — el reflejo moderno de las del original

| Original (clases del binario) | Nuevo |
|---|---|
| AppKit + skins BMP propios (MmSkin, MmKnob, MmSliderCtrl, MmVuMeter) | SwiftUI + AppKit donde haga falta; modo oscuro; arm64 nativo |
| Controladores (TimelineController, PlaylistController, TweaksController…) | Modelos observables en Swift, uno por panel |
| Interfaces de servicio (IMixManager, IPerformPlayManager, IPreviewPlayManager, ICategoryManager, IMidiManager) | Mismos cinco servicios, como protocolos Swift sobre la API C del núcleo |
| Motor (MmEngine, MmSongSlicer, Resampler) | **Motor propio desde cero** en `engine/` (C++20). Decisión del 20-10-2026: no se reutiliza mm2027 |
| Análisis «Pf» (CProfileBuilder, BeatPattern, KeyDetector, Fingerprint) | `engine/` — ritmo hecho y validado (`engine/docs/VALIDACION.md`); tonalidad y estructura pendientes |
| Core Data `MmCatalog.mom` + cola `ProfileWorkItem` | SQLite con migraciones; la cola de análisis en paralelo, no persistida en serie |
| QTKit / Fraunhofer MP3 | AVFoundation para leer y para exportar AAC; MP3 con un codificador de licencia revisada |
| VST2 + 7 AIR | Alojamiento AUv3 (`AVAudioUnit`) + unos pocos efectos propios |
| CoreMIDI + `miditemplates.xml` | CoreMIDI con *MIDI learn*; plantillas propias |
| DiscRecording, ScriptingBridge/iTunes, PACE | Fuera; importación desde Apple Music y rekordbox |

## Compatibilidad hacia atrás

Leer siempre, sin pedir nada: el catálogo de MixMeister, los `.mxm` y los `.mmp`.
Escribir `.mmp` es deseable para poder volver al original mientras conviva.

## Estado del motor (20-10-2026)

Hecho y validado en `engine/`: E/S de audio, FFT, ritmo (tempo, fase, compás), tonalidad,
ventanas de mezcla, WSOLA, transiciones y sesiones `.mmp` → WAV + CUE. Cifras en
`engine/docs/VALIDACION.md`. Siguiente: reproducción en tiempo real (doble salida), los 13
tipos de transición de `transitions.xml`, escribir `.mmp`, y la app (M0 de abajo).

## Hoja de ruta

Cada hito se da por terminado cuando sus filas de `01-MAPA-FUNCIONAL.md` pasan a
✅ **con una prueba que lo mide**, no cuando la pantalla existe.

| Hito | Contenido | Filas que cierra |
|---|---|---|
| M0 | Esqueleto: app + núcleo enlazado + biblioteca SQLite que importa la de MixMeister | Biblioteca: añadir, columnas, buscar |
| M1 | Segmentos: partir, recortar, alargar, invertir, solo, encaje fino | Línea de tiempo |
| M2 | Automatización con varios puntos (volumen y 3 bandas) | Línea de tiempo |
| M3 | Directo completo: doble salida, Mix Now, parar y preparar, pistas pinchadas | Directo |
| M4 | Efectos AUv3 por pista y en el master, con marcadores de parámetro | Efectos |
| M5 | Biblioteca completa: categorías, listas inteligentes, etiquetas, Tweaks | Biblioteca, Lista |
| M6 | Salidas: MP3/AAC, escribir `.mmp`; MIDI y *learn* | Salidas, Directo |

## Riesgos

- **Codificar MP3**: LAME es LGPL; enlazarlo dinámicamente o exportar AAC por defecto.
- **AUv3**: alojar plug-ins de terceros dentro del hilo de audio exige aislarlos; un plug-in que cuelga no puede tumbar el directo.
- **Doble salida**: dos dispositivos de audio con relojes distintos derivan; o dispositivo agregado, o una tarjeta de 4 canales.
