#!/bin/bash
# Development tool, not part of the shipped app.
#
# Wraps LogilightsCLI in a minimal signed .app bundle. Reading HID++ replies
# goes through the HID stack, which macOS gates behind Input Monitoring — and
# that permission can only be granted to something with a stable code
# signature. A binary from `swift run` has none, so IOHIDManagerOpen fails
# with kIOReturnNotPermitted (0xe00002e2) no matter what.
#
#   ./scripts/build-probe-app.sh
#   ./build/LogilightsProbe.app/Contents/MacOS/LogilightsCLI hidpp-features-hid 046d c092
#
# The first run raises an Input Monitoring prompt; approve it, then run again.
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE="build/LogilightsProbe.app"
IDENTIFIER="io.github.eag75.LogilightsProbe"

echo "==> Building (release)"
swift build -c release --product LogilightsCLI

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/LogilightsCLI" "$BUNDLE/Contents/MacOS/"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>LogilightsCLI</string>
	<key>CFBundleIdentifier</key><string>$IDENTIFIER</string>
	<key>CFBundleName</key><string>LogilightsProbe</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing"
codesign --force --sign - --identifier "$IDENTIFIER" --timestamp=none "$BUNDLE"
codesign --verify --strict "$BUNDLE"

echo "==> Done: $BUNDLE"
