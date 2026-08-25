#!/usr/bin/env bash
# Build and launch Marbles without Xcode (useful when xcodebuild plugins are broken).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/Marbles/Sources"
OUT="$ROOT/apps/Marbles/build/Marbles.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14.0"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"

cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Marbles</string>
  <key>CFBundleIdentifier</key>
  <string>dev.marbles.app</string>
  <key>CFBundleName</key>
  <string>Marbles</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Marbles receives local status from Claude Code hooks on this Mac.</string>
</dict>
</plist>
PLIST

mkdir -p "$OUT/Contents/Resources" "$ROOT/apps/Marbles/build"
cp "$ROOT/apps/Marbles/Resources/Shaders/Marble.metal" "$OUT/Contents/Resources/Marble.metal"
if xcrun -sdk macosx metal -c "$ROOT/apps/Marbles/Resources/Shaders/Marble.metal" \
  -o "$ROOT/apps/Marbles/build/Marble.air" -mmacosx-version-min=14.0 2>/dev/null
then
  xcrun -sdk macosx metallib "$ROOT/apps/Marbles/build/Marble.air" \
    -o "$OUT/Contents/Resources/default.metallib" 2>/dev/null || true
fi

xcrun swiftc -parse-as-library -O -DDEBUG -sdk "$SDK" -target "$TARGET" \
  -framework AppKit -framework SwiftUI -framework Network -framework Metal -framework MetalKit \
  -o "$OUT/Contents/MacOS/Marbles" \
  $(find "$SRC" -name '*.swift' | sort)

mkdir -p "$OUT/Contents/Helpers"
xcrun swiftc -O -sdk "$SDK" -target "$TARGET" \
  -framework Security \
  -o "$OUT/Contents/Helpers/marbles-hook" \
  "$SRC/Agents/IngestConstants.swift" \
  "$SRC/Ingest/IngestAuth.swift" \
  "$ROOT/tools/marbles-hook/main.swift"

pkill -x Marbles 2>/dev/null || true
open "$OUT"
echo "Launched $OUT"
echo "Ingest POST http://127.0.0.1:17832/hook with X-Marbles-Token from ~/Library/Application Support/Marbles/ingest.json"
