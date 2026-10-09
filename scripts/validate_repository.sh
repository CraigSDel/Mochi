#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

./check_code_line_lengths.sh
bash -n start_llama_network.sh start_ollama_network.sh
git diff --check

if command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
  xcrun swift-format lint --recursive Sources Tests
else
  echo "swift-format is unavailable; install it with the supported Xcode toolchain." >&2
  exit 1
fi

if rg -n 'brew[[:space:]]+install|(^|[[:space:]])sudo[[:space:]]' start_llama_network.sh start_ollama_network.sh; then
  echo "Launchers must not install dependencies or elevate privileges." >&2
  exit 1
fi

CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/cache/clang}" \
SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT/.build/cache/swiftpm}" \
swift test
