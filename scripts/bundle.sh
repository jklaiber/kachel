#!/bin/bash
# Build Kachel.app (an .app bundle keeps the Accessibility permission
# attached to the app instead of to your terminal).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Kachel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Kachel "$APP/Contents/MacOS/Kachel"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: ./scripts/make-icon.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>io.github.jklaiber.kachel</string>
    <key>CFBundleName</key>            <string>Kachel</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleExecutable</key>      <string>Kachel</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# macOS ties the Accessibility grant to the code signature. An ad-hoc
# signature changes with every build, which silently invalidates the grant.
# Set SIGN_IDENTITY to a real certificate (e.g. "Apple Development: …", see
# `security find-identity -v -p codesigning`) to keep it across rebuilds.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
    # Drop the now-stale grant so macOS prompts again instead of showing the
    # toggle as "on" while AXIsProcessTrusted() returns false.
    tccutil reset Accessibility io.github.jklaiber.kachel >/dev/null 2>&1 || true
    echo "Ad-hoc signed: re-grant Accessibility after launching (set SIGN_IDENTITY to avoid this)."
fi
echo "Built $APP"
echo "Run:   open $APP"
