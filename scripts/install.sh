#!/usr/bin/env bash
# Engineer path: build (if needed), copy to /Applications, launch.
# First launch installs hooks and may show a demo marble.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Marbles.app"
DEST="/Applications/Marbles.app"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/package.sh"
fi

echo "Installing $APP → $DEST"
pkill -x Marbles 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
# Unsigned builds need a right-click Open anyway the first time (Gatekeeper).
open "$DEST" || {
  echo "If macOS blocked the app: right-click Marbles in /Applications and choose Open."
  exit 1
}
echo "Launched $DEST"
echo "Menu bar extra → Setup shows hook + app detection. Undo Hooks removes only Marbles entries."
