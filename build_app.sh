#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/Local AI Controller.app"
CONTENTS="$APP_DIR/Contents"

mkdir -p "$BUILD_DIR/cache/clang" "$BUILD_DIR/cache/swiftpm" "$ROOT/dist"
CLANG_MODULE_CACHE_PATH="$BUILD_DIR/cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/cache/swiftpm" \
swift build --disable-sandbox -c release -debug-info-format none --package-path "$ROOT"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_DIR/release/LocalAIController" "$CONTENTS/MacOS/LocalAIController"
cp "$ROOT/start_llama_network.sh" "$ROOT/start_ollama_network.sh" "$CONTENTS/Resources/"
cp "$ROOT/AppResources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/LocalAIController" "$CONTENTS/Resources/"*.sh
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
