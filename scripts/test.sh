#!/usr/bin/env bash
# Compile and run Marbles unit tests without Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/Marbles/Sources"
TESTS="$ROOT/apps/Marbles/Tests"
OUT="$ROOT/apps/Marbles/build/marbles-tests"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14.0"

mkdir -p "$(dirname "$OUT")"

xcrun swiftc -parse-as-library -O -sdk "$SDK" -target "$TARGET" \
  -framework AppKit \
  -o "$OUT" \
  "$SRC/Agents/Models.swift" \
  "$SRC/Agents/AgentRoster.swift" \
  "$SRC/Mode/ModeController.swift" \
  "$SRC/Layout/SnapGeometry.swift" \
  "$SRC/Layout/LayoutEngine.swift" \
  "$TESTS/TestSupport.swift" \
  "$TESTS/LayoutTests.swift" \
  "$TESTS/ModeTests.swift" \
  "$TESTS/main.swift"

"$OUT"
