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
</dict>
</plist>
PLIST

xcrun swiftc -parse-as-library -O -DDEBUG -sdk "$SDK" -target "$TARGET" \
  -framework AppKit -framework SwiftUI \
  -o "$OUT/Contents/MacOS/Marbles" \
  $(find "$SRC" -name '*.swift' | sort)

pkill -x Marbles 2>/dev/null || true
open "$OUT"
echo "Launched $OUT"
