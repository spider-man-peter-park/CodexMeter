#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/module-cache}"
swift build -c release "$@"
BIN_DIR="$(swift build -c release "$@" --show-bin-path)"
STAGE="$(mktemp -d /private/tmp/codexmeter-app.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/CodexMeter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CodexMeter" "$APP/Contents/MacOS/CodexMeter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/ditto --norsrc "$BIN_DIR/CodexMeter_CodexMeterApp.bundle" "$APP/Contents/Resources/CodexMeter_CodexMeterApp.bundle"
/usr/bin/ditto --norsrc "$BIN_DIR/CodexMeter_CodexMeterCore.bundle" "$APP/Contents/Resources/CodexMeter_CodexMeterCore.bundle"
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
OUTPUT_DIR="${CODEXMETER_OUTPUT_DIR:-$PWD/build}"
mkdir -p "$OUTPUT_DIR"
DEST_APP="$OUTPUT_DIR/CodexMeter.app"
PREVIOUS_APP="$STAGE/Previous.app"
if [[ -e "$DEST_APP" ]]; then
    mv "$DEST_APP" "$PREVIOUS_APP"
fi
if ! /usr/bin/ditto --norsrc "$APP" "$DEST_APP" \
    || ! /usr/bin/codesign --verify --strict "$DEST_APP" \
    || ! "$DEST_APP/Contents/MacOS/CodexMeter" --verify-resources; then
    rm -rf "$DEST_APP"
    if [[ -e "$PREVIOUS_APP" ]]; then
        mv "$PREVIOUS_APP" "$DEST_APP"
    fi
    exit 1
fi
printf 'Built %s\n' "$OUTPUT_DIR/CodexMeter.app"
