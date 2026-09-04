#!/usr/bin/env bash
# Build a launchable Marbles.app into dist/ (no Debug menu).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/Marbles/Sources"
OUT="$ROOT/dist/Marbles.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14.0"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Helpers"

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
  <key>NSAppleEventsUsageDescription</key>
  <string>Marbles brings the terminal tab running a session to the front when you click its marble.</string>
</dict>
</plist>
PLIST

cp "$ROOT/apps/Marbles/Resources/Shaders/Marble.metal" "$OUT/Contents/Resources/Marble.metal"
if xcrun -sdk macosx metal -c "$ROOT/apps/Marbles/Resources/Shaders/Marble.metal" \
  -o "$ROOT/dist/Marble.air" -mmacosx-version-min=14.0 2>/dev/null
then
  xcrun -sdk macosx metallib "$ROOT/dist/Marble.air" \
    -o "$OUT/Contents/Resources/default.metallib" 2>/dev/null || true
fi

xcrun swiftc -parse-as-library -O -sdk "$SDK" -target "$TARGET" \
  -framework AppKit -framework SwiftUI -framework Network -framework Metal -framework MetalKit -framework ServiceManagement \
  -o "$OUT/Contents/MacOS/Marbles" \
  $(find "$SRC" -name '*.swift' | sort)

xcrun swiftc -O -sdk "$SDK" -target "$TARGET" \
  -framework Security \
  -o "$OUT/Contents/Helpers/marbles-hook" \
  "$SRC/Agents/IngestConstants.swift" \
  "$SRC/Agents/TerminalContext.swift" \
  "$SRC/Ingest/IngestAuth.swift" \
  "$ROOT/tools/marbles-hook/main.swift"

ditto -c -k --keepParent "$OUT" "$ROOT/dist/Marbles.zip"
echo "Built $OUT"
echo "Zipped $ROOT/dist/Marbles.zip"
