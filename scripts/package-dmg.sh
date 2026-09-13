#!/bin/bash
# Empaqueta ConBarAI.app y crea el DMG con destino /Applications (drag-to-install).
# Uso: bash scripts/package-dmg.sh   → dist/ConBarAI-<versión>.dmg
set -Eeuo pipefail
cd "$(dirname "$0")/.."

VER="$(./.build/release/conbarai --version 2>/dev/null || echo 0.0.0)"
ROOT="dist/root"
APP="$ROOT/ConBarAI.app"
echo "▸ ConBarAI v$VER"

swift build -c release

rm -rf "$ROOT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/conbarai "$APP/Contents/MacOS/conbarai"
cp icons/ConBarAI.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R skills "$APP/Contents/Resources/skills"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ConBarAI</string>
    <key>CFBundleDisplayName</key><string>ConBarAI</string>
    <key>CFBundleIdentifier</key><string>dev.conbarai.macos</string>
    <key>CFBundleVersion</key><string>$VER</string>
    <key>CFBundleShortVersionString</key><string>$VER</string>
    <key>CFBundleExecutable</key><string>conbarai</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT — 686f6c61</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
EOF

# Firma ad-hoc: sin ella, macOS broker bloquea el primer arranque más feo aún.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign ad-hoc no disponible; el DMG seguirá funcionando)"

# Enlace a /Applications para arrastrar
ln -sfn /Applications "$ROOT/Applications"

DMG="dist/ConBarAI-$VER.dmg"
rm -f "$DMG"
hdiutil create -volname "ConBarAI" -srcfolder "$ROOT" -ov -format UDZO "$DMG" >/dev/null
echo "▸ $DMG"
hdiutil imageinfo "$DMG" 2>/dev/null | grep -E "Format:|Size" | head -2 || true
echo "Listo. El usuario arrastra ConBarAI a /Applications y ejecuta una vez:"
echo "  /Applications/ConBarAI.app/Contents/MacOS/conbarai setup"
echo "  (o doble clic: al ser LSUIElement no abre ventana; el setup es el paso 2 del README)"
