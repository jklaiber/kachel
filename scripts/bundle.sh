#!/bin/bash
# Build XMonadMac.app (an .app bundle keeps the Accessibility permission
# attached to the app instead of to your terminal).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/XMonadMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/XMonadMac "$APP/Contents/MacOS/XMonadMac"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>local.xmonadmac</string>
    <key>CFBundleName</key>            <string>XMonadMac</string>
    <key>CFBundleExecutable</key>      <string>XMonadMac</string>
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
    tccutil reset Accessibility local.xmonadmac >/dev/null 2>&1 || true
    echo "Ad-hoc signed: re-grant Accessibility after launching (set SIGN_IDENTITY to avoid this)."
fi
echo "Built $APP"
echo "Run:   open $APP"
