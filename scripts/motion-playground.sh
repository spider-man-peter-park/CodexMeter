#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat <<'HELP'
Usage: scripts/motion-playground.sh [--build-only | --launch | --projection | --stop | --test]

  --build-only  Build and verify only the standalone OrbMotionPlayground product.
  --launch      Build, then launch it inside the retained isolated preview (default).
  --projection  Build, then launch Projection mode in the same retained preview.
  --stop        Stop the retained preview without building or replacing anything.
  --test        Run motion, localization and state-preservation tests.

The production CodexMeter application is not rebuilt or replaced by this script.
HELP
}

MODE="${1:---launch}"
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi
case "$MODE" in
    --help|-h)
        usage
        exit 0
        ;;
    --stop)
        exec scripts/preview-app.sh --stop
        ;;
    --test)
        exec scripts/test.sh --build-system native --disable-sandbox --filter '(OrbMotionKitTests|ProjectionMotionKitTests|PlaygroundLocalizationTests|PlaygroundAppTests)'
        ;;
    --build-only|--launch|--projection)
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/module-cache}"
BUILD_FLAGS=(-c release --product OrbMotionPlayground --disable-sandbox --build-system native)
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
"$BIN_DIR/OrbMotionPlayground" --verify-resources

OUTPUT_DIR="$PWD/build/motion-playground"
mkdir -p "$OUTPUT_DIR"
STAGED_BINARY="$(mktemp "$OUTPUT_DIR/.OrbMotionPlayground.XXXXXX")"
trap 'rm -f "$STAGED_BINARY"' EXIT
cp "$BIN_DIR/OrbMotionPlayground" "$STAGED_BINARY"
chmod 755 "$STAGED_BINARY"
"$STAGED_BINARY" --verify-resources
mv -f "$STAGED_BINARY" "$OUTPUT_DIR/OrbMotionPlayground"
printf 'Verified standalone binary: %s\n' "$OUTPUT_DIR/OrbMotionPlayground"

if [[ "$MODE" == --projection ]]; then
    scripts/preview-app.sh --motion-playground --launch -- --ui-preview-fixtures --projection-playground
elif [[ "$MODE" == --launch ]]; then
    scripts/preview-app.sh --motion-playground --launch -- --ui-preview-fixtures
fi
