#!/bin/sh
# Compara el motor con los .mxm de MixMeister: cada audio con su .mxm al lado (mismo nombre).
# Uso: sh tools/validar.sh carpeta [carpeta...]   (necesita build/mmn compilado)
set -e
D="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-validacion.tsv}"
: > "$OUT"
for dir in "$@"; do
  for a in "$dir"/*.mp3 "$dir"/*.wav; do
    [ -f "$a" ] || continue
    m="${a%.*}.mxm"
    [ -f "$m" ] && "$D/build/mmn" tsv "$a" "$m" >> "$OUT" || true
  done
done
python3 "$D/tools/resumen.py" "$OUT"
