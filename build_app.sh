#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/Mochi.app"
CONTENTS="$APP_DIR/Contents"

"$ROOT/check_code_line_lengths.sh" || exit 1

mkdir -p "$BUILD_DIR/cache/clang" "$BUILD_DIR/cache/swiftpm" "$ROOT/dist"
CLANG_MODULE_CACHE_PATH="$BUILD_DIR/cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/cache/swiftpm" \
swift build --disable-sandbox -c release -debug-info-format none --package-path "$ROOT"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_DIR/release/Mochi" "$CONTENTS/MacOS/Mochi"
cp "$ROOT/start_llama_network.sh" "$CONTENTS/Resources/"
cp "$ROOT/AppResources/AppIcon.png" "$CONTENTS/Resources/AppIcon.png"
cp "$ROOT/AppResources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/AppResources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/Mochi" "$CONTENTS/Resources/"*.sh
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
