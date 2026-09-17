#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT=$(cd "$(dirname "$0")" && pwd)

violations=0

# Find all authored code files and check line counts
while IFS= read -r -d '' file; do
    lines=$(wc -l < "$file")
    if [[ $lines -gt 300 ]]; then
        echo "${file#$ROOT/}:${lines}"
        violations=1
    fi
done < <(
    find "$ROOT" \
        \( -path "$ROOT/.git" -prune \) -o \
        \( -path "$ROOT/.kilo" -prune \) -o \
        \( -path "$ROOT/.build" -prune \) -o \
        \( -path "$ROOT/dist" -prune \) -o \
        \( -name "*.xcodeproj" -prune \) -o \
        \( -name "*.xcworkspace" -prune \) -o \
        \( -name "AppResources" -prune \) -o \
        \( -name "*.png" -prune \) -o \
        \( -name "*.icns" -prune \) -o \
        \( -name "*.md" -prune \) -o \
        \( \
            -name "*.swift" -o \
            -name "*.sh" -o \
            -name "*.py" -o \
            -name "*.js" -o \
            -name "*.ts" -o \
            -name "*.c" -o \
            -name "*.cpp" -o \
            -name "*.h" -o \
            -name "*.hpp" -o \
            -name "*.m" -o \
            -name "*.mm" -o \
            -name "Package.swift" -o \
            -name "*.json" -o \
            -name "*.yaml" -o \
            -name "*.yml" -o \
            -name "*.toml" \
        \) -type f -print0 2>/dev/null
)

exit $violations