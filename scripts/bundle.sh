#!/bin/bash
# Build Kachel.app (an .app bundle keeps the Accessibility permission
# attached to the app instead of to your terminal).
set -euo pipefail
cd "$(dirname "$0")/.."

# VERSION=0.2.0 sets the version shown in Finder; UNIVERSAL=1 builds for
# Apple Silicon and Intel in one binary (what releases ship).
VERSION="${VERSION:-0.0.0-dev}"
ARCHS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then ARCHS=(--arch arm64 --arch x86_64); fi

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Kachel"

APP="build/Kachel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kachel"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: ./scripts/make-icon.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>io.github.jklaiber.kachel</string>
    <key>CFBundleName</key>            <string>Kachel</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleExecutable</key>      <string>Kachel</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# macOS ties the Accessibility grant to the code signature. An ad-hoc
# signature changes with every build, which silently invalidates the grant.
# Signed with the same certificate every time, the grant stays. Releases use
# the self-signed "Kachel Signing" certificate (from the KACHEL_SIGNING_P12
# secret); locally it's used when it's in your keychain. SIGN_IDENTITY
# overrides, SIGN_IDENTITY=- forces ad-hoc.
if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Kachel Signing"'; then
    SIGN_IDENTITY="Kachel Signing"
fi
if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with \"$SIGN_IDENTITY\": the Accessibility grant survives rebuilds."
else
    codesign --force --sign - "$APP"
    # Drop the now-stale grant so macOS prompts again instead of showing the
    # toggle as "on" while AXIsProcessTrusted() returns false.
    tccutil reset Accessibility io.github.jklaiber.kachel >/dev/null 2>&1 || true
    echo "Ad-hoc signed: re-grant Accessibility after launching (see docs/development.md)."
fi
echo "Built $APP"
echo "Run:   open $APP"
