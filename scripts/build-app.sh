#!/bin/bash
# Builds build/LingoBar.app from the Swift package (no Xcode needed).
#
# Signing: uses $LINGOBAR_SIGN_IDENTITY if set, else the first valid codesigning
# identity in the keychain, else ad-hoc ("-"). Ad-hoc signatures change on every
# build, so macOS forgets Screen Recording / Accessibility grants after each rebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/LingoBar.app"
VERSION="0.1.0"
BUNDLE_ID="io.github.if-route.lingobar"

cd "$ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LingoBar" "$APP/Contents/MacOS/LingoBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LingoBar</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LingoBar</string>
    <key>CFBundleDisplayName</key>
    <string>LingoBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

IDENTITY="${LINGOBAR_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/^ *[0-9]+\)/ {print $2; exit}')"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "Signing: ad-hoc (no codesigning identity found). macOS will ask for Screen Recording again after each rebuild."
else
    echo "Signing with identity: $IDENTITY"
fi
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "Built $APP"
