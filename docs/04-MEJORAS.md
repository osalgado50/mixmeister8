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

## Siguiente (propuesto, por orden de valor)

1. **Normalización de sonoridad (LUFS)** al exportar (−14 / −9 LUFS, true peak −1 dBTP) y medidor
   LUFS en el master.
2. **Forma de onda por frecuencias** (graves rojo, medios verde, agudos azul) en la línea de tiempo
   y el Song Slicer, para ver los bombos y cuadrar a ojo.
3. **Sugerencia de siguiente pista** («Find Similar» mejorado): puntuación por tonalidad, BPM y
   energía, y ordenar una lista automáticamente para que fluya.
4. **Grabación de la sesión en directo** (lo que sale por la salida principal a un fichero).
5. **Salida a 48 kHz y exportación a FLAC** (MP3 cuando haya un codificador libre de licencias en
   macOS).
6. **Rendimiento en directo**: montar solo las pistas cercanas al cursor (ahora se montan todas las
   que quedan), menos CPU con listas largas.
7. **Pruebas automáticas** de regresión en el Mac: render de 5 listas de referencia y comparación
   bit a bit con la versión anterior en cada compilación.
8. **Análisis de BPM/tonalidad en paralelo** al añadir muchos ficheros a la biblioteca.
