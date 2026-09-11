#!/usr/bin/env bash
# Engineer path: build, copy to /Applications, launch.
# First launch installs hooks and may show a demo marble.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Marbles.app"
DEST="/Applications/Marbles.app"

# Always rebuild. This used to skip the build whenever dist/Marbles.app existed, which meant an
# edit-then-install cycle silently installed the *previous* build and still said "Launched" —
# you would go looking for a bug in code that was never in the binary. package.sh wipes dist/
# and rebuilds from scratch anyway, so there is no build to reuse and nothing to be saved by
# guessing. Pass --no-build to install a dist/ you deliberately built yourself.
if [[ "${1:-}" == "--no-build" ]]; then
  [[ -d "$APP" ]] || { echo "No build at $APP; run scripts/package.sh first." >&2; exit 1; }
  echo "Skipping build; installing the existing $APP"
else
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
