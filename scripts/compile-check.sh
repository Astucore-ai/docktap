#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/docktap-compile-check}"
swiftc -swift-version 5 -O \
  -target arm64-apple-macos13.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -o "$OUT" \
  "$ROOT"/Sources/*.swift
echo "compile ok: $OUT"
