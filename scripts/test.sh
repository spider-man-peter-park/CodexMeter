#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/module-cache}"
SWIFT_BIN="$(xcrun --find swiftc)"
TEST_PLUGINS="$(dirname "$SWIFT_BIN")/../lib/swift/host/plugins/testing"
FLAGS=()
if [[ -d "$TEST_PLUGINS" ]]; then
    FLAGS+=(-Xswiftc -plugin-path -Xswiftc "$TEST_PLUGINS")
fi
TEST_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    FLAGS+=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" -Xlinker -F -Xlinker "$TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS")
fi
swift test --disable-xctest --enable-swift-testing "${FLAGS[@]}" "$@"
