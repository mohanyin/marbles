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
  "$SRC/Agents/LatticeSlots.swift" \
  "$SRC/Agents/FixtureFiles.swift" \
  "$SRC/Identity/Identity.swift" \
  "$SRC/Agents/IngestConstants.swift" \
  "$SRC/Agents/HookEvent.swift" \
  "$SRC/Agents/HookMapper.swift" \
  "$SRC/Agents/TranscriptPeek.swift" \
  "$SRC/Agents/SeedStore.swift" \
  "$SRC/Agents/AgentStore.swift" \
  "$SRC/Ingest/IngestAuth.swift" \
  "$SRC/Motion/MotionEngine.swift" \
  "$SRC/Chips/Chips.swift" \
  "$SRC/Focus/FocusPreview.swift" \
  "$SRC/Hooks/JSONC.swift" \
  "$SRC/Hooks/Hooks.swift" \
  "$SRC/Persistence/PrefsStore.swift" \
  "$SRC/Demo/DemoMarble.swift" \
  "$SRC/Mode/ModeController.swift" \
  "$SRC/Layout/SnapGeometry.swift" \
  "$SRC/Layout/LayoutEngine.swift" \
  "$TESTS/TestSupport.swift" \
  "$TESTS/LayoutTests.swift" \
  "$TESTS/ModeTests.swift" \
  "$TESTS/StatusTests.swift" \
  "$TESTS/HookMapperTests.swift" \
  "$TESTS/IngestAuthTests.swift" \
  "$TESTS/MotionTests.swift" \
  "$TESTS/IdentityTests.swift" \
  "$TESTS/FocusPreviewTests.swift" \
  "$TESTS/HooksMergeTests.swift" \
  "$TESTS/DemoTests.swift" \
  "$TESTS/main.swift"

"$OUT"

HELPER="$ROOT/apps/Marbles/build/marbles-hook"
xcrun swiftc -O -sdk "$SDK" -target "$TARGET" \
  -framework Security \
  -o "$HELPER" \
  "$SRC/Agents/IngestConstants.swift" \
  "$SRC/Ingest/IngestAuth.swift" \
  "$ROOT/tools/marbles-hook/main.swift"

set +e
printf 'not-json' | "$HELPER"
BAD_EXIT=$?
printf '' | "$HELPER"
EMPTY_EXIT=$?
set -e
if [[ "$BAD_EXIT" -ne 0 || "$EMPTY_EXIT" -ne 0 ]]; then
  echo "hook helper must exit 0 (got bad=$BAD_EXIT empty=$EMPTY_EXIT)"
  exit 1
fi
echo "Hook helper contract passed"
