# Validación del motor — estado a 20-10-2026

Todo lo que sigue sale de ejecutar `build/mmn_tests`, `mmn` y los scripts de `tools/` sobre
datos reales; nada es estimado. Los resultados por pista están en `../validacion/`.

## Plataformas

| Dónde | Compilador | Pruebas | Avisos |
|---|---|---|---|
| Nube, Linux x86_64 | gcc 13 y clang 18 | 19 casos, 74 comprobaciones | 0 |
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

## Contra MixMeister — tu biblioteca (212 pistas, 83-163 BPM)

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

## Pendiente

- Compás en pistas con anacrusa o intro irregular (21 % restante).
- Fase: 11 a contratiempo, 17 con desfase intermedio (¿tempo que deriva?).
- Tempo variable (directos): hoy la rejilla es de tempo constante.
- Los 13 tipos de transición de `transitions.xml` (hoy, cruce a potencia constante).
- Escribir `.mmp`; reproducción en tiempo real; interfaz.
