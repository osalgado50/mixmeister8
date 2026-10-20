#!/bin/sh
# Monta "MixMeister 8.app" a partir de lo compilado con `swift build -c release`.
# Uso (en el Mac, desde la carpeta del repositorio): app/bundle.sh
set -e
cd "$(dirname "$0")/.."
BIN=".build/release/MixMeister8"
[ -x "$BIN" ] || swift build -c release
APP="build/MixMeister 8.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MixMeister 8"
cp app/Resources/Info.plist "$APP/Contents/Info.plist"
[ -f app/Resources/AppIcon.icns ] && cp app/Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
