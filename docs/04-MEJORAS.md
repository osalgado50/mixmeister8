# MixMeister 8 — mejoras sobre el original (rendimiento, estabilidad, calidad, funciones)

Una vez copiada la operativa de MixMeister 7.8, esto es lo que MixMeister 8 hace mejor. Cada punto
lleva cómo se ha medido en el Mac Pro (macOS 26, 32 núcleos) con Spinning310 (24 pistas, 47:33).

## Hecho y medido (21-10-2026)

### Calidad de audio
| Mejora | Antes | Ahora | Cómo se comprueba |
|---|---|---|---|
| Camino bit a bit: una pista a su tempo y en su tono no pasa por el cambio de tempo, ni por el EQ si no tiene marcadores | todas pasaban por AUNewTimePitch (vocoder de fase) y el EQ | idéntica al audio decodificado: 1 764 000 de 1 764 000 muestras, 0 de desfase | `--nulltest` frente a `afconvert` |
| Volumen sin escalones (DSP propio, suavizado de 3 ms; a 0 dB no toca el audio) | `player.volume` a saltos cada 23 ms (fichero) o 16 ms (directo): «zipper» en los fundidos | salto máximo entre muestras ÷3,3 en el peor caso de prueba | prueba del motor |
| Limitador del master transparente (anticipación 1,5 ms, umbral −0,3 dBFS) | Apple Peak Limiter con −1 dB fijo: toda la mezcla 1 dB más baja y procesada | por debajo del umbral, idéntico (retraso de 66 muestras, descontado al exportar) | prueba del motor y `--nulltest` |
| Dither TPDF al pasar a 16 bits (fichero y CD) | truncado sin dither (distorsión en pasajes suaves) | ruido blanco a −96 dB | código |
| WAV y AIFF de 24 bits | solo 16 bits | elegible en Export | — |
| Cambio de tempo con más calidad (solape 16, antes 8) | — | menos artefactos en las pistas con el tempo cambiado | — |
| **Sincronía de las pistas con el tempo cambiado** (en directo y al exportar) | se desplazaban de su sitio: −155 ms (a 0,98), +188 ms (a 1,04), +41 ms (a 1,0001) en 5 min | ±3 ms en 5 min en todas | `--synctest` + medición por transitorios |
| Sincronía en una lista real (Spinning310, comparado con el audio original de cada pista) | pistas 6 y 8: +27…+92 ms | 0…2 ms | `--where` + `onset3.py` |

**Por qué se desplazaban:** AUNewTimePitch avanza por saltos de entrada enteros de 4096/overlap
muestras, así que la velocidad real es round(H·v)/H (medido y comprobado con 0,98, 1,0417 y 1,10, a
solape 8 y 16); y a velocidad exactamente 1,0 cambia de modo y su retardo salta. MixMeister 8 lleva la
cuenta del audio que consume de verdad con ese modelo, la compara con donde debe ir según la mezcla y
pide en cada momento el salto entero que lo corrige (nunca 1,0). Coste: las pistas a velocidad casi
exacta de 1 ya no van por el atajo interno del AU; en directo la mezcla entera usa ~18 % de un núcleo
(render seguido de Spinning310: 526 s para 47:33). No sirve medirlo con `playerTime(forNodeTime:)`: es una conversión lineal
del reloj, no cuenta lo consumido (comprobado).

### Velocidad
| Mejora | Antes | Ahora |
|---|---|---|
| Exportación en paralelo: cada pista en su motor (sin cortarla), suma final con master y limitador | 280,6 s (un solo núcleo) | 18,7 s (×15), igual que el render seguido (desfase ≤ 0,4 ms) |
| Formas de onda en caché de disco | 1,57 s al abrir Spinning310 | 0,60 s |

### Estabilidad
- Cambio de dispositivo de audio (desenchufar, cambiar la frecuencia): se vuelve a montar el grafo y
  sigue sonando donde iba (AVAudioEngineConfigurationChange).
- Copia de recuperación cada minuto con cambios sin guardar; si la app se cierra de golpe, al abrirla
  ofrece recuperarla (comprobado con `--crashtest`).

### Funciones nuevas
- Biblioteca: con una pista seleccionada en la lista se resaltan las que mezclan bien con ella
  (tonalidad compatible en el círculo de quintas y BPM a menos de un 6 %, o doble/mitad).
- Seis skins (View › Skin).

## Segunda tanda (21-10-2026): las 7 propuestas, hechas y medidas

| # | Mejora | Resultado medido en el Mac |
|---|---|---|
| 1 | **Normalización de sonoridad** al exportar (No / −14 / −11 / −9 / −16 LUFS, pico real ≤ −1 dBTP) y **medidor LUFS** (corto plazo, 3 s) junto a los vúmetros | base.mmp a −14 → −14,02 LUFS; a −9 → −9,17 (pico −1,5 dBTP). Medidor propio BS.1770-4 = ffmpeg ebur128 ±0,1 LU |
| 2 | **Forma de onda por frecuencias** (graves rojo, medios verde, agudos azul), View › Color Waveforms | se ven los bombos; la caché de disco guarda las bandas |
| 3 | **Find Similar** (tonalidad + BPM + género; con BPM a más de un ~15 % no sugiere) y **Tools › Order Playlist for Harmonic Flow** | Spinning310: compatibilidad media entre pistas seguidas 0,375 → 0,635 |
| 4 | **Grabar la sesión en directo** (Playback › Record Mix…, ⌥⌘R): WAV de 24 bits de la salida del master | 4,00 s grabados en 4 s de reproducción |
| 5 | **48 kHz y FLAC** (y WAV/AIFF de 24 bits) | FLAC a 48 kHz correcto (ffprobe) |
| 6 | **Menos CPU en directo**: solo se montan las pistas cercanas al cursor; el cursor redibuja solo su franja; la forma de onda solo se recorre en la zona sucia y en color se agrupa en 64 colores | Spinning310 en directo: a los 5 min 115 % → 22 % de un núcleo; a los 31 min 104 % → 33 %. Pistas montadas a la vez: 4–6 en vez de 22 |
| 7 | **Pruebas de regresión automáticas** (`sh tests/regresion.sh`, 16 comprobaciones) | ver abajo |

**Normalización cuando hay que subir mucho:** si para llegar al objetivo los picos pasarían de −1 dBTP,
la ganancia va antes del limitador (techo −1,5 dBFS) y se busca por la secante (hasta 3 medidas,
±0,2 LU), porque el limitador comprime y la sonoridad sube menos que la ganancia. Si el limitador tiene
que recortar más de 6 dB, al terminar sale un aviso («puede sonar aplastada»). Ejemplo real: base.mmp
tiene el 42 % de sus bloques con picos a menos de 6 dB del máximo; para llegar a −9 LUFS hace falta
+16,9 dB antes del limitador (≈ 11 dB de recorte), y se avisa.

**CPU:** el coste en directo no era el audio sino el dibujo: el cursor redibujaba toda la línea de
tiempo 60 veces por segundo, y la forma de onda en color creaba un color por píxel que Core Animation
procesaba uno a uno (medido con `sample`: el 98 % del hilo principal en `CA::Transaction::commit`).

### Pruebas de regresión (`tests/regresion.sh`, en el Mac)
Efectos propios (15) · ida y vuelta de todas las listas .mmp sin cambiar un byte (640 de 640) ·
bit a bit (882 000 de 882 000 muestras) · sincronía a 117,6 / 120,016 / 125 BPM (≤ 10 ms en 5 min) ·
exportación en paralelo = render seguido · normalización a −14 y −9 LUFS (±0,5 LU, ≤ −1 dBTP) ·
reproducción en directo · grabación · copia de recuperación tras cierre brusco · exportación de la
lista grande (< 40 s) · ordenar por flujo · Find Similar · CPU en directo (< 60 %).

## Siguiente (propuesto)

1. **Análisis de BPM/tonalidad en paralelo** al añadir muchos ficheros a la biblioteca.
2. **MP3** al exportar cuando haya un codificador libre de licencias en macOS.
3. **Efecto en parte de una pista** y **Save as Tweak** (pendientes de la copia del original).
