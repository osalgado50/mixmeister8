#!/bin/sh
# Reproduce todo el inventario a partir del instalador original.
# Uso: sh tools/extraer.sh "/ruta/MixMeister Studio.pkg" /ruta/salida
# Requiere: python3, gzip, cpio. Para los nibs, REA (ver ../mm2027/tools/rea-setup.sh).
set -e
PKG="$1"; OUT="$2"; T="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT/root"
python3 -I "$T/xar_extract.py" "$PKG" "$OUT" >/dev/null
(cd "$OUT/root" && gzip -dc "$OUT"/*.pkg/Payload | cpio -idm 2>/dev/null)
APP="$OUT/root/Applications/MixMeister Studio.app"
python3 -I "$T/mom.py" "$APP/Contents/Resources/MmCatalog.mom" > "$OUT/core-data.md"
if command -v rea >/dev/null; then
  rea decode-interface-builder "$APP" --format json > "$OUT/ib.json"
  python3 -I "$T/ib_summary.py" "$OUT/ib.json" "$OUT/ui-nibs.md"
fi
echo "Hecho en $OUT"
