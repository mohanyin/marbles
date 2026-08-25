#!/usr/bin/env bash
# Remove Marbles.app and Marbles-owned hooks. Pass --purge to delete Application Support.
set -euo pipefail

DEST="/Applications/Marbles.app"
PURGE=0
if [[ "${1:-}" == "--purge" ]]; then
  PURGE=1
fi

if [[ -x "$DEST/Contents/MacOS/Marbles" ]]; then
  "$DEST/Contents/MacOS/Marbles" --uninstall-hooks || true
elif [[ -x "$(dirname "$0")/../apps/Marbles/build/Marbles.app/Contents/MacOS/Marbles" ]]; then
  "$(dirname "$0")/../apps/Marbles/build/Marbles.app/Contents/MacOS/Marbles" --uninstall-hooks || true
fi

rm -rf "$DEST"
echo "Removed $DEST"

if [[ "$PURGE" -eq 1 ]]; then
  rm -rf "$HOME/Library/Application Support/Marbles"
  echo "Removed Application Support/Marbles"
else
  echo "Left ~/Library/Application Support/Marbles (pass --purge to delete)"
fi
