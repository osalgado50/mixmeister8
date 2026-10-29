# Validación del motor — estado a 29-10-2026

Todo lo que sigue sale de ejecutar `build/mmn_tests`, `mmn` y los scripts de `tools/` sobre
datos reales; nada es estimado. Los resultados por pista están en `../validacion/`.

## Plataformas

| Dónde | Compilador | Pruebas | Avisos |
|---|---|---|---|
| Nube, Linux x86_64 | gcc 13 y clang 18 | 21 casos, 97 comprobaciones | 0 |
| **macOS 26.6, Mac Pro Intel** | Apple clang (Xcode) | ídem | 0 |

## Pruebas con verdad conocida

| Prueba | Criterio | Resultado |
|---|---|---|
| FFT compleja / real frente a DFT directa | error relativo < 2e-5 | pasa |
| Remuestreo, WAV ida y vuelta | | pasa |
| Tempo a 120, 128, 133,3 y 174 BPM | \|ΔBPM\| < 0,01 | pasa |
| Fase del primer tiempo | ±2 ms | pasa (−0,3 … +0,6 ms) |
| Temblor humano, 22 050 / 48 000 Hz, ruido sin pulso | | pasa |
| Primer tiempo que suena tras silencio | exacto | pasa |
| Tonalidad: 24 tonalidades sintéticas, Camelot, MIREX | ≥ 22/24 | pasa |
| WSOLA a velocidad 1 | idéntico (< 1e-5) | pasa |
| WSOLA: tono a 0,92 / 1,05 / 1,12 | < 1 Hz sobre 440 | pasa |
| WSOLA: tempo pedido / mapa en rampa sin deriva | ±0,05 BPM / ±15 ms | pasa |
| Transición 124 → 130 | cada lado a su tempo, golpes alineados | pasa |
| Lector `.mmp` y búsqueda de audio por nombre | | pasa |

Aviso conocido: en un groove sintético con silencio delante, la regla de compás aprendida
puede desplazar el compás un tiempo (`WARN` en la prueba). En música real acierta el 79 %.

## Contra MixMeister — biblioteca completa (4175 pistas con su `.mxm`, 29-10-2026)

Toda la carpeta SWAT DJ's: cada fichero (MP3, M4A, WAV) frente al `.mxm` que escribió
MixMeister 7.8. En el Mac Pro, 24 en paralelo (`/tmp/mm8val.sh`, resumen con
`tools/resumen2.py`). Cada columna es una versión del motor sobre las mismas 4175 pistas.

| | v5 (20-10) | v7 | v8 | **v9 (actual)** |
|---|---|---|---|---|
| Mismo nivel métrico | 96,8 % | 96,8 % | 98,0 % | **98,0 %** (4091) |
| Fase (< 0,1 tiempos) | 77,3 % | 86,3 % | 86,0 % | **89,5 %** |
| Compás (con la fase bien) | 82,8 % | 84,0 % | 84,0 % | **87,2 %** |
| Las tres bien | 62 % | 70,2 % | 70,8 % | **76,4 %** |
| Tiempo por pista (4,4 min de media, 24 a la vez) | 3,03 s | 2,12 s | 2,10 s | **2,11 s** |
| Biblioteca entera | 540 s | 384 s | 381 s | **382 s** |

Qué cambió en cada paso:

- **v6-v7, línea de tiempo de MixMeister.** El desfase de fase era sobre todo del decodificador:
  MixMeister adelanta el audio 375 muestras respecto a minimp3 y, según la cabecera del MP3,
  suma o no el retardo del codificador (LAME/Xing/Info); en M4A va 282 muestras por detrás de
  Core Audio; WAV sin cambio. Con eso, mediana del desfase −0,23 ms (MP3), −0,85 ms (M4A),
  +0,18 ms (WAV); el 70 % de las pistas a menos de 10 ms de MixMeister. Además FFT, rejilla y
  envolvente con Accelerate (vDSP/vForce): un 30 % menos de tiempo.
- **v8, rango de MixMeister.** En las 4175 pistas MixMeister nunca da menos de 82 BPM y solo 7
  pasan de 162: lee un DnB a 174 como 87. El motor pliega por octavas a [80, 166)
  (`TempoOptions::fold_min_bpm/fold_max_bpm`; `MMN_FOLD=0` en `mmn` para el tempo sin plegar).
- **v9, fase a cuartos de tiempo y compás reajustado.** Regla nueva (`quarter_score`): las cuatro
  rejillas a P/4 compiten (8 rasgos de ataque/caída por banda + bombo) y solo cambia si otra gana
  por margen 0,25. Validación cruzada 89,4 % (sin ella 86,6 %). Compás: 7 rasgos sobre 3492
  pistas, margen 1 frente a la convención; validación cruzada 87,0 % (antes 83,9 %).

Lo que queda: 84 pistas a otro nivel (66 sin relación simple: clásica, ambiente, cortes de 3 s
de cuenta atrás, donde la cifra de MixMeister es arbitraria; 7 a 4:3), 156 a más de 0,1 BPM de
MixMeister (rock en directo con tempo que deriva, y pistas de estudio donde el motor da la cifra
redonda — 128,002, 150,000 — y MixMeister no), y 190 a contratiempo.

## GiantSteps Tempo (661 pistas EDM anotadas, tempo sin plegar)

| Motor | Accuracy1 (±4 %) | Accuracy2 (también ×2, ×½, ×3, ×⅓) | Tiempo por pista (2 min) |
|---|---|---|---|
| v9 | **83,1 %** | **93,9 %** | 0,83 s |

Los fallos de Accuracy1 son casi todos de octava (×2: 45, ×½: 27), que es justo donde las
anotaciones de GiantSteps dudan entre 87 y 174. `tools/gs_tempo.py`.

## Contra MixMeister — primera biblioteca (212 pistas, 83-163 BPM, 20-10-2026)

Cada pista frente al `.mxm` que escribió MixMeister. En el Mac Pro, 16 en paralelo.

| | v1 (mañana) | **v5 (actual)** |
|---|---|---|
| Ficheros leídos | 188 (sin `.m4a`) | **212** |
| Mismo nivel métrico | 96,3 % | **98,6 %** (209/212) |
| Diferencia de tempo, mediana | 0,0051 BPM | **0,0047 BPM** |
| Fase (< 0,1 tiempos) | 55,8 % | **85,6 %** |
| Compás (cuando la fase está bien) | 58,4 % | **79,3 %** |
| Tiempo por pista (media 3 min 50 s) | 2,5 s | 2,3 s |

Las tres reglas aprendidas, con su validación cruzada (pistas que no entraron en el ajuste):

| Regla | Rasgos | Validación cruzada | Antes |
|---|---|---|---|
| Fase: tiempo o contratiempo | 8 (ataque y caída por banda) | **88,9 %** ± 5,6 | 60 % |
| *(v9) Fase a cuartos de tiempo* | *8 + bombo, 3412 pistas* | *89,4 %* | *86,6 %* |
| *(v9) Compás* | *7 + convención, 3492 pistas* | *87,0 %* | *83,9 %* |
| Compás | 3 (graves, armonía, novedad) + convención | **78,6 %** | 60 % |
| Nivel métrico | 6 (pulso, coherencia, distancia a 120) | **99,5 %** | 98,6 % |

Las 11 demos del instalador, que no entraron en ningún ajuste: 11/11 en tempo y fase, 9/11
en compás.

**Donde discrepamos de MixMeister en tempo, a menudo acierta el motor nuevo**: loops con el
tempo en el nombre, `lostsoul_135` (MixMeister 134,31 / nuevo 134,98), `drm125` (125,28 /
124,98), `FHP_130` (128,67 / 129,81).

**Quedan 3 fallos de nivel**: «Drive (83 Bpm)» doblada, una en relación 3:4 (105 frente a 140)
y una a 87,5 frente a 91. Las dos últimas están fuera de la familia de candidatos.

## Tonalidad — GiantSteps Key (604 pistas anotadas a mano)

| Método | MIREX |
|---|---|
| Primer cromagrama (todos los bins, amplitud log) | 0,16 (azar) |
| Cromagrama por picos + afinación + armónicos, perfil Temperley | 0,444 |
| ídem, perfil Krumhansl | 0,542 |
| **ídem, perfiles aprendidos (validación cruzada 10 partes)** | **0,652** ± 0,047 |

0,652 está en el rango de los mejores métodos clásicos de perfiles publicados (0,65-0,66).
Las redes neuronales llegan a ~0,74.

## Ventanas de mezcla — contra los `.mxm` (195 pistas)

| | Resultado |
|---|---|
| Ventanas de 32 tiempos (8 compases) en MixMeister | 98 % |
| Fin de salida a un número entero de frases desde la entrada | 97 % |
| Entrada: nuestra regla exacta / ±1 compás | 60 % / 88 % |
| Salida: nuestra regla exacta | 77 % |

## Mezcla — comprobada midiendo la salida

*Take a Ride* (120) → *The Other Side* (128): principio 119,996 BPM, solape 124,6 (centro de
la rampa), final 128,004; pico 0,98, ninguna muestra saturada.
Lista de muestra de MixMeister (5 pistas, 3:49): cada tramo a su tempo (130 / 130 / 130 /
130 / 135), niveles −10 a −13 dBFS, sin saturar.

## Errores propios encontrados y corregidos durante la validación

- Fase enganchada al contratiempo por los charles (y luego por el bajo): regla aprendida.
- Compás: ventana de búsqueda del ataque desplazada respecto al pico real.
- FFT: `std::complex<float>::operator*` llamaba a `__mulsc3` (70 % del tiempo).
- Tonalidad: cromagrama aplanado por la batería.
- Mezcla: saturación en el solape (dos temas en fase); limitador con anticipación.
- Prueba de WAV que escribía en la carpeta actual (fallaba al ejecutar desde `/`).
- `mmn phasediag`: leía la banda del frame −1 en pistas que empiezan en el primer frame; se
  caía y `xargs` cortaba el diagnóstico a las 405 primeras pistas.
- Desfase de fase del decodificador (375 muestras + retardo LAME): ver la línea de tiempo de
  MixMeister arriba.

## Pendiente

- Compás en pistas con anacrusa o intro irregular (13 % restante en la biblioteca completa).
- Fase: 190 de 4091 a contratiempo; el resto de desfases, sobre todo en pistas con tempo que deriva.
- Tempo variable (directos): hoy la rejilla es de tempo constante.
- Los 13 tipos de transición de `transitions.xml` (hoy, cruce a potencia constante).
- Escribir `.mmp`; reproducción en tiempo real; interfaz.
