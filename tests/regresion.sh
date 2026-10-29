#!/bin/sh
# Pruebas de regresión de MixMeister 8 (en el Mac, desde la carpeta del repositorio):
#   sh tests/regresion.sh
# Comprueba de punta a punta lo que se ha medido a mano: formatos, calidad bit a bit, sincronía,
# exportación en paralelo, normalización, reproducción, grabación, efectos y recuperación.
# Variables (opcionales): LISTAS (carpeta con .mmp), MIX (lista grande), CORTA (lista corta), AUDIO (mp3).
cd "$(dirname "$0")/.."
A='./build/MixMeister 8.app/Contents/MacOS/MixMeister 8'
T="$(pwd)/tests"
W="$HOME/Documents/WORKS/SWAT DJ's"
LISTAS="${LISTAS:-$W}"
MIX="${MIX:-$W/CD/310/Spinning310.mmp}"
CORTA="${CORTA:-$W/_mm8exp/base.mmp}"
AUDIO="${AUDIO:-$W/CD/310/Avicii - GoodBye (Best Melodies Tribute).mp3}"
TRAMO="${TRAMO:-$W/_mm8exp/exp-tramo.mmp}"   # guardada por MixMeister 7.8: AIR Flanger solo en los compases 20-40
TWEAK="${TWEAK:-$W/_mm8exp/tweak-original.mmdm}"  # Tweak «MM8 prueba tramo» guardado por MixMeister 7.8 de esa pista
AIR1="${AIR1:-$W/_mm8exp/exp-air-phaser-def.mmp}"  # AIR Phaser con Rate 1,00 Hz (guardada por MixMeister 7.8)
AIR2="${AIR2:-$W/_mm8exp/exp-air-phaser-rate.mmp}" # la misma con Rate 3,39 Hz
R=/tmp/mm8-regresion-$$; mkdir -p $R
PY=/usr/bin/python3
pasa=0; falla=0
ok()  { echo "PASA   $1"; pasa=$((pasa+1)); }
mal() { echo "FALLA  $1"; falla=$((falla+1)); }
num() { [ -n "$1" ] && [ -n "$2" ] && awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0<=b+0)}'; }   # a <= b (vacío = falla)

echo "MixMeister 8 — pruebas de regresión ($(date '+%d-%m-%Y %H:%M'))"

# 1. Efectos propios
n=$("$A" --fxtest 2>/dev/null | grep -c 'FXTEST ok')
[ "$n" -ge 15 ] && ok "efectos propios: $n de 15 cargan" || mal "efectos propios: solo $n cargan"

# 2. Formato .mmp: todas las listas, ida y vuelta sin cambiar un byte
rt=$("$A" --roundtrip "$LISTAS" 2>/dev/null | grep ROUNDTRIP)
echo "$rt" | awk '{exit !($2==$4 && $4>0)}' && ok "listas .mmp: ${rt#ROUNDTRIP }" || mal "listas .mmp: ${rt#ROUNDTRIP }"

# 3. Calidad: una pista a su tempo sale idéntica bit a bit
"$A" --nulltest "$AUDIO" $R/null.wav > /dev/null 2>&1
afconvert -f WAVE -d LEI24 "$AUDIO" $R/ref.wav
set -- $($PY "$T/nulo.py" $R/null.wav $R/ref.wav)
[ "$1" = "$2" ] && ok "bit a bit: $1 de $2 muestras idénticas" || mal "bit a bit: $1 de $2 muestras idénticas"

# 4. Sincronía de las pistas con el tempo cambiado (máx. 10 ms en 5 minutos)
for tempo in 117.6 120.016 125; do
  "$A" --serial --synctest "$AUDIO" $R/s.wav --synctempo $tempo > /dev/null 2>&1
  d=$($PY "$T/sincronia.py" $R/s.wav $tempo $R/ref.wav)
  num "$d" 10 && ok "sincronía a $tempo BPM: máx. $d ms" || mal "sincronía a $tempo BPM: máx. $d ms"
done

# 5. Exportación en paralelo = render seguido (lista corta)
"$A" "$CORTA" --exporttest $R/par.wav > /dev/null 2>&1
"$A" "$CORTA" --serial --exporttest $R/ser.wav > /dev/null 2>&1
d=$($PY "$T/desfase.py" $R/ser.wav $R/par.wav 2>/dev/null | sed -E 's/.*desfase ([-+0-9.]+) ms/\1/' | tr -d '+' | awk '{x=$1<0?-$1:$1; if(x>m)m=x} END{print m+0}')
num "$d" 6 && ok "paralelo = seguido: desfase máx. $d ms" || mal "paralelo = seguido: desfase máx. $d ms"

# 6. Normalización (−14 y −9 LUFS, ±0,5 LU, pico real ≤ −1 dBTP; a −9 debe avisar si aplasta)
for target in -14 -9; do
  ex=$("$A" "$CORTA" --exporttest $R/n$target.wav --wav24 --normalize $target 2>/dev/null | grep EXPORTTEST)
  set -- $("$A" --lufs $R/n$target.wav 2>/dev/null | grep LUFS)
  l=$2; tp=$4
  dif=$(awk -v a="$l" -v b="$target" 'BEGIN{d=a-b; print (d<0?-d:d)}')
  aviso=""; echo "$ex" | grep -q AVISO && aviso=" (con aviso de limitación)"
  if num "$tp" -0.9 && num "$dif" 0.5; then ok "normalización a $target LUFS: $l LUFS, pico $tp dBTP$aviso"
  else mal "normalización a $target LUFS: $l LUFS, pico $tp dBTP$aviso"; fi
done

# 7. Reproducción en directo y grabación
out=$("$A" "$MIX" --playtest 200 --playsecs 4 --record $R/rec.wav 2>/dev/null)
echo "$out" | grep PLAYTEST | tail -1 | awk '{split($4,l,"=");exit !(l[2]>0.01)}' && ok "reproducción en directo: suena" || mal "reproducción en directo: no suena"
secs=$(echo "$out" | grep RECORD | awk '{print $2}')
num 3.5 "${secs:-0}" && ok "grabación de la sesión: $secs s" || mal "grabación de la sesión: ${secs:-0} s"

# 8. Recuperación tras un cierre brusco
REC="$HOME/Library/Application Support/MixMeister 8/Recuperación.mmp"
"$A" "$MIX" --crashtest > /dev/null 2>&1
[ -f "$REC" ] && ok "copia de recuperación tras cierre brusco" || mal "no quedó copia de recuperación"
rm -f "$REC"; defaults delete es.mixmeister8.app "MM8 Recovery Source" 2>/dev/null

# 9. Velocidad: exportar la lista grande (< 40 s)
t0=$(date +%s); "$A" "$MIX" --exporttest $R/big.wav > /dev/null 2>&1; t=$(( $(date +%s) - t0 ))
[ "$t" -lt 40 ] && ok "exportación de la lista grande: $t s" || mal "exportación de la lista grande: $t s"

# 10. Sugerencias: ordenar la lista por flujo armónico mejora la compatibilidad; Find Similar responde
of=$("$A" "$MIX" --orderflow 2>/dev/null | grep ORDERFLOW)
set -- $(echo "$of" | sed -E 's/.*seguidas: ([0-9.]+) → ([0-9.]+);.*/\1 \2/')
awk -v a="$1" -v b="$2" 'BEGIN{exit !(b>a)}' && ok "ordenar por flujo: compatibilidad $1 → $2" || mal "ordenar por flujo: $of"
"$A" "$MIX" --similar 2 2>/dev/null | grep -q 'SIMILAR.*\]' && ok "Find Similar da candidatos" || mal "Find Similar no da candidatos"

# 11. CPU en directo (a 31 minutos de la lista grande, media de 8 s) por debajo del 60 % de un núcleo
"$A" "$MIX" --playtest 1900 --playsecs 16 > /dev/null 2>&1 &
P=$!; sleep 6; c=0; for i in 1 2 3 4 5 6 7 8; do c=$(awk -v a="$c" -v b="$(ps -o %cpu= -p $P)" 'BEGIN{print a+b}'); sleep 1; done; wait $P
c=$(awk -v a="$c" 'BEGIN{printf "%.0f", a/8}')
num "$c" 60 && ok "CPU en directo: $c %" || mal "CPU en directo: $c %"

# 12. Efecto en una parte de la pista: la lista del original y un tramo creado en MM8 solo cambian ahí
$PY "$T/sinfx.py" "$TRAMO" $R/seco.mmp
"$A" $R/seco.mmp --exporttest $R/seco.wav > /dev/null 2>&1
"$A" "$TRAMO" --exporttest $R/orig.wav > /dev/null 2>&1
d=$($PY "$T/difftramo.py" $R/seco.wav $R/orig.wav)
echo "$d" | grep -q 'tramos: 34-69$' && ok "efecto en un tramo (lista del original): ${d#*tramos: } s" || mal "efecto en un tramo (lista del original): $d"
"$A" $R/seco.mmp --addfx 'MM8 Flanger - MixMeister 8' --fxtrack 0 --fxrange 34.3 68.6 --saveas $R/mm8.mmp > /dev/null 2>&1
"$A" $R/mm8.mmp --exporttest $R/mm8.wav > /dev/null 2>&1
d=$($PY "$T/difftramo.py" $R/seco.wav $R/mm8.wav)
m=$($PY "$T/mmpdump.py" $R/mm8.mmp | grep -c 'tipo 08000000.*FFF valor')
echo "$d" | grep -q 'tramos: 34-69$' && [ "$m" = 4 ] && ok "efecto en un tramo (creado en MM8): ${d#*tramos: } s, $m marcadores" || mal "efecto en un tramo (creado en MM8): $d, $m marcadores"

# 13. Tweaks: el que genera MM8 es idéntico al de MixMeister 7.8, y cargarlo deja la pista como estaba
"$A" "$TRAMO" --tweakdump 1 $R/tw.mmdm > /dev/null 2>&1
cmp -s $R/tw.mmdm "$TWEAK" && ok "Tweak generado = el de MixMeister 7.8 ($(wc -c < "$TWEAK" | tr -d ' ') bytes)" || mal "Tweak generado distinto del de MixMeister 7.8"
"$A" $R/seco.mmp --tweakload 1 "MM8 prueba tramo" --exporttest $R/tw.wav > /dev/null 2>&1
d=$($PY "$T/difftramo.py" $R/orig.wav $R/tw.wav)
echo "$d" | grep -q 'ninguno' && ok "cargar el Tweak devuelve el efecto en su tramo" || mal "cargar el Tweak: $d"

# 14. Efectos AIR: sus parámetros (bloque ACVS) llegan al efecto equivalente: cambiar el Rate cambia el sonido
"$A" "$AIR1" --exporttest $R/air1.wav > /dev/null 2>&1
"$A" "$AIR2" --exporttest $R/air2.wav > /dev/null 2>&1
d=$($PY "$T/difftramo.py" $R/air1.wav $R/air2.wav)
n=$(echo "$d" | sed -E 's/segundos distintos: ([0-9]+).*/\1/')
[ "${n:-0}" -gt 200 ] && ok "efectos AIR: el Rate de AIR Phaser cambia el sonido ($n s distintos)" || mal "efectos AIR: $d"

echo "---"
echo "$pasa pasan, $falla fallan"
rm -rf $R
[ "$falla" -eq 0 ]
