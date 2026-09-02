#!/bin/bash
# Builds Logilights.app — a proper bundle, which SMAppService needs in order
# to register the app as a login item (it is a no-op under `swift run`).
#
#   ./scripts/build-app.sh              build into ./build/Logilights.app
#   ./scripts/build-app.sh --install    also copy it to /Applications
#
# Signing: ad-hoc by default, which is enough to run locally. Set
# SIGN_IDENTITY to a Developer ID to produce something distributable, e.g.
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Logilights"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" means ad-hoc

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$APP_NAME"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Signing (identity: $SIGN_IDENTITY)"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    # SMAppService keys login items to the bundle's location, so replace in
    # place rather than leaving copies around.
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "    /Applications/$APP_NAME.app"
fi

echo "==> Done: $APP_BUNDLE"
