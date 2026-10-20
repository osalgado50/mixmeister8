# Formato de lista `.mmp` (MixMeister 7.x) — especificación

Formato estudiado para interoperar (Directiva 2009/24/CE, art. 6). No sale del código de
MixMeister: sale de **observar ficheros** y de **experimentos controlados**. Se partía de una lista
de una pista, se añadía en MixMeister Studio 7.8 un solo elemento desde el menú
(volumen, agudos, medios, graves, etiqueta, bucle, corte, inversión, tono, overlay), se guardaba
y se comparaba. Los ficheros de esos experimentos están en `engine/validacion/mmp-experimentos/`.

Implementación: `engine/include/mmn/mmp.hpp`. Validación: **652 de 652 listas reales se leen y se
reescriben idénticas byte a byte** (`mmn mmp-check`): 627 de la biblioteca SWAT DJ's (2008-2026,
hechas en Windows y en Mac, 10 445 pistas), 3 del corpus de investigación, la de muestra del
instalador y 11 de los experimentos.

Todo es *little-endian*. Las cadenas van en UTF-16LE con un cero final. Las posiciones están en
**microsegundos del audio original** (contrastado con la duración real de los MP3: el segmento de
*Red Lights* acaba en 200 306 939 µs y el MP3 dura 200,28 s).

## Árbol

```
RIFF "MXMP"
├─ LIST "TRKL"                    lista de pistas, en orden de reproducción
│  └─ LIST "TRKI"  (una por pista)
│     ├─ TRKH   56 B              cabecera de pista
│     ├─ TRKF                     ruta del audio (tal como la guardó: C:\…, Z:\…, /Users/…, \\host\…)
│     ├─ TRSI   (opcional)        transición de entrada («Beatmix 8», «Beatmix Full», «Simple Crossfade», «No Transition»…)
│     ├─ TRSO   (opcional)        transición de salida
│     ├─ LIST "TKTM"              mapa de tempo original (Beat Slicer)
│     │  ├─ TKTH  8 B             i64: microsegundos por compás → BPM = 240·10⁶ / valor
│     │  ├─ TRKM  32 B × n        marcadores de compás (tipo 0x10000000)
│     │  └─ TRKS  32 B            la pista entera (puede ir antes o entre los TRKM: se respeta el orden)
│     ├─ LIST "TKEL"              efectos de la pista
│     │  └─ EFXT  × n
│     └─ LIST "TKLY"              capa de mezcla: marcadores y segmentos, en el orden en que estaban
│        ├─ TRKM  32/36/38… B
│        └─ TRKS  32 B (principal) o 52 B (overlay)
├─ LIST "GLBL"                    ajustes de la mezcla
│  ├─ GBIN  8 B                   +0 u32 8 · +4 f32 volumen master (dB)
│  └─ EFXT  × n                   efectos del master
└─ MMVR  12 B                     +0 u32 12 · +4 u32, +8 u32: versión (7.8 Mac escribe 0x00070000 0x00040001)
```

## TRKH — cabecera de pista (56 bytes)

| Offset | Tipo | Significado | Cómo se sabe |
|---|---|---|---|
| +0 | u32 | 0x38 (tamaño) | fijo en 10 445 pistas |
| +8 | 16 B | **identificador del audio** = `ZMUSICFILEID` del catálogo (en hex, en el mismo orden) | Alexia: `FBC2F3E7-C031-9914-…` en los dos |
| +24 | u32 | **BPM × 1000** | 139 985 en la pista de 139,985 BPM |
| +32 | u16 | 2 | fijo |
| +34 | u16 | **estilo: 1 principal, 2 overlay** | experimento *overlay* |
| +36 | u32 | 0x00220001 casi siempre (¿mezcla de tiempos / tamaño de rebanada?) | sin confirmar |
| +40 | f32 | **ajuste de tono (semitonos)** | experimento *key*: 2,0 |
| +44 | u32 | 1 (14 pistas con 4) | sin confirmar |
| +48 | i32 | −2 (6 pistas con 2 o 4) | sin confirmar |
| +52 | u32 | 0 (12 pistas con 0xFFF) | sin confirmar |

Lo que no está confirmado se conserva tal cual al reescribir.

## TRKM — marcador (32 bytes; las etiquetas, más)

| Offset | Tipo | Significado |
|---|---|---|
| +0 | u16 | 0x20 |
| +2 | u16 | 1 |
| +4 | u32 | **tipo** (tabla) |
| +8 | i64 | posición (µs del audio original) |
| +16 | u32 | indicador 0/1 |
| +20 | f32 | valor: dB (volumen, ecualización) o BPM (tempo) |
| +24 | u32 | etiquetas: caracteres del texto con el cero |
| +32 | UTF-16 | etiquetas: texto |

| Tipo | Elemento de MixMeister | Valor | Confirmado |
|---|---|---|---|
| 0x00000001 | ancla de entrada (*Intro*) | — | aparece una por pista principal; el fundido de entrada nace en ella |
| 0x00000002 | ancla de salida (*Outro*) | — | el fundido automático de salida empieza en ella |
| 0x00000080 | volumen de la mezcla por defecto (entrada) | dB (−50 … 0) | observado: rampa −50 → −6 → 0 dB en la ancla de entrada |
| 0x00000100 | volumen de la mezcla por defecto (salida) | dB | experimento base: 0, −6, −50 dB al final |
| 0x00008000 | Add Volume Marker | dB | experimento |
| 0x00010000 | Add Treble Marker | dB | experimento |
| 0x00020000 | Add Midrange Marker | dB | experimento |
| 0x00040000 | Add Bass Marker | dB | experimento |
| 0x01000000 | Add Tempo Marker | BPM | experimento base (139,99) |
| 0x02000000 | Add Original Tempo Marker | BPM | = 240·10⁶ / TKTH |
| 0x04000000 | Add Label Marker | texto («1», «2»… por defecto) | experimento |
| 0x08000000 | Add Effects Parameter Marker | | presente en listas reales; falta experimento |
| 0x10000000 | marcador de compás (Beat Slicer) | — | en TKTM; a veces copiado en TKLY |
| 0x40000000 | Add Loop Start Marker | — | experimento |
| 0x80000000 | Add Loop End Marker | — | experimento |

## TRKS — segmento (32 bytes; overlays, 52)

| Offset | Tipo | Significado |
|---|---|---|
| +0 | u16 | 0x20 |
| +2 | u16 | bit 0: **al revés** (*Reverse*) |
| +4 | u32 | 1 pista principal · 2 overlay |
| +8 | i64 | inicio en el audio (µs) |
| +16 | i64 | fin en el audio (µs) |
| +24 | i64 | punto de arranque: el inicio, o el fin si va al revés |
| +32 | u16, u16 | overlays: 2, 0x12 |
| +36 | i32 | overlays: compás de la mezcla donde cae |
| +40 | f32 | overlays: fracción de compás |
| +44 | f64 | overlays: 1,0 (velocidad) |

*Split Segment at Cursor* convierte un TRKS en dos contiguos (el segundo empieza 1 µs después del
fin del primero).

## EFXT — efecto

| Offset | Tipo | Significado |
|---|---|---|
| +0 | u32 | 36 (cabecera) |
| +4 | u32 | identificador VST del plug-in |
| +20 | u32 | posición en el rack |
| +24 | u32 | indicadores |
| +28 | u32 | bytes de parámetros |
| +32 | u32 | caracteres del nombre, con el cero |
| +36 | f32 × n | parámetros normalizados 0..1 |
| luego | UTF-16 | nombre («MultiLimit», «NewBlue dj Stereoizer», «NewBlue dj Parametric EQ», «TBK3 Stereo»…) |

Los efectos originales son plug-ins de terceros (AIR, NewBlue), con licencia, que MixMeister 8 no
puede incluir. La lista los conserva intactos y MixMeister 8 los asocia a efectos propios
equivalentes por su identificador (pendiente: tabla de correspondencias).

## Pendiente de experimento

Effects Parameter Marker; Tweaks y Quick Save Tweak; marcadores de tempo desde la regla; los
campos sin confirmar de TRKH; el contenido de los 13 tipos de transición personalizados
(«Simple Custom», «Beatmix Custom»), que guardan sus ajustes en los marcadores.
