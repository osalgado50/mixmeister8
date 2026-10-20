# Validación del motor — estado a 20-10-2026

Todo lo que sigue sale de ejecutar `build/mmn_tests` y `tools/validar.sh`; nada es estimado.

## Plataformas comprobadas

| Dónde | Compilador | Pruebas | Avisos | Demos |
|---|---|---|---|---|
| Nube, Linux x86_64 | gcc 13 y clang 18 | 37/37 | 0 | 11/11 al mismo tempo |
| VM Linux del Mac | gcc 11 | 37/37 | — | idénticas |
| **macOS 26.6, Mac Pro Intel** | Apple clang (Xcode) | 37/37 | 0 | idénticas, ~0,56 s por pista; lee `.m4a` |

## Pruebas sintéticas (verdad exacta) — 37/37

| Prueba | Criterio | Resultado |
|---|---|---|
| FFT compleja contra DFT directa (2…1024 puntos) e inversa | error relativo < 2e-5 | pasa |
| FFT real contra compleja (2048) | < 1e-3 | pasa |
| Remuestreo 48 → 44,1 kHz de un tono de 1 kHz | error < 2e-3, duración exacta | pasa |
| WAV escribir/leer a 16 bits | error < 1/16384 | pasa |
| Tempo a 120, 128, 133,333 y 174 BPM | \|ΔBPM\| < 0,01 | pasa |
| Fase del primer tiempo en esos cuatro tempos | ±2 ms | pasa (medido: −0,3 … +0,6 ms) |
| Temblor humano de 8 ms + ruido, 126 BPM | \|ΔBPM\| < 0,02 | pasa |
| Material a 22 050 y 48 000 Hz | \|ΔBPM\| < 0,01 | pasa |
| Compás 1 tras 0, 1, 2, 3 y 6 tiempos de silencio | exacto | pasa |
| Ruido sin pulso | confianza < ¼ de la de un groove | pasa |

## Contra MixMeister Studio 7.8 — las 11 demos del instalador

Cada MP3 frente al `.mxm` que el propio MixMeister escribió.

| | Resultado |
|---|---|
| Mismo nivel métrico (no 64 por 128) | **11 / 11** |
| Diferencia de tempo | mediana **0,006 BPM**, máxima 0,038 BPM (0,03 %) |
| Fase: la entrada de mezcla de MixMeister cae sobre un tiempo nuestro | **11 / 11**, a −4,7 … −15,7 ms (mediana −7,2 ms) |
| Compás: esa entrada es nuestro tiempo 1 | **11 / 11** |
| Tiempo de análisis | ~1 s por pista de 52-78 s, en 2 núcleos de nube |

*Music Is Your Life*, que se enganchaba a contratiempo, quedó resuelta con la regla de fase aprendida (ver abajo).

**Los −7 ms** son sistemáticos: MixMeister marca sus tiempos un poco antes del ataque que
nosotros medimos (nuestra fase está calibrada a ±1 ms contra ataques sintéticos). Para
mezclar es inaudible; para leer y escribir `.mxm` se puede compensar con una constante.

## Contra MixMeister — tu biblioteca real (212 pistas, 83-163 BPM, media 3 min 50 s)

Ejecutado en el Mac Pro, 16 análisis en paralelo: ~40 s para las 212. Resultados por pista
en `validacion/`.

| | v1 (mañana) | **v2 (actual)** |
|---|---|---|
| Ficheros leídos | 188 / 212 (sin `.m4a`) | **212 / 212** — `.m4a` vía Core Audio |
| Mismo nivel métrico | 181 / 188 (96,3 %) | **206 / 212 (97,2 %)** |
| Diferencia de tempo (mediana) | 0,005 BPM | **0,005 BPM** |
| Fase correcta (< 0,1 tiempos) | 101 / 181 (55,8 %) | **178 / 206 (86,4 %)** |
| A contratiempo | 63 | **11** |
| Compás, cuando la fase está bien | 59 / 101 | 107 / 178 (60 %) |

**Fase.** La regla tiempo/contratiempo es una regresión logística con 8 rasgos (ataque y caída
en subgraves, graves, medios y agudos), ajustada con `mmn phasediag` sobre esta biblioteca.
Validación cruzada en 10 partes: **88,9 % ± 5,6 %**. Las 11 demos del instalador, que no
entraron en el ajuste, dan **11/11**. Rehacer: `tools/ajustar_fase.py`.

**Nivel.** El prior pasó de 128 a 120 BPM tras barrer 12 configuraciones
(`validacion/prior-barrido-*.tsv`): 120 con anchura 0,5 octavas es la mejor; ensancharlo
empeora mucho. Quedan 6 fallos: 3 lentas dobladas (una se llama «Drive (83 Bpm)»), 2 rápidas
partidas por la mitad (150 y 160 BPM, efecto del prior) y 1 en 3:4. Un prior fijo no basta.

**Tempo.** En las mayores discrepancias acierta el motor nuevo: loops con el tempo en el
nombre, `lostsoul_135` (MixMeister 134,31 / nuevo 134,98), `drm125` (125,28 / 124,98),
`FHP_130` (128,67 / 129,81).

## Qué se aprendió del original al validar

- **El compás 1 de MixMeister es el primer tiempo con sonido.** En 10 de las 11 demos su
  entrada está a 1024 muestras exactas del inicio de la región analizada, y todos sus puntos
  de mezcla caen a múltiplos de 4 tiempos contados desde ahí. Se adoptó esa convención; un
  detector de compás por cambio armónico acertaba 3 de 11 y se retiró.
- **La autocorrelación premia los tempos lentos** en música en bucle; el nivel lo decide la
  fuerza del pulso bajo cada tiempo, probando T, 2T, T/2, 3T/2 y 2T/3.
- **El fundamental de banda ancha se engancha al contratiempo** (charles). La fase se ancla
  a la coincidencia de graves y ataque: el bombo.

## Pendiente de validar

- **Compás**: 60 %. La convención «primer tiempo que suena» falla con anacrusas e intros
  irregulares. Siguiente prioridad.
- **Nivel métrico** sin prior fijo (6 fallos).
- Fase: 11 a contratiempo y 17 con desfase intermedio (¿tempo que deriva?).
- Tempo variable (directos, música no electrónica): hoy la rejilla es de tempo constante.
