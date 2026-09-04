# Marbles

A native macOS overlay for local coding agents. **arm64, macOS 14+.** Not notarized yet.

## Install (under five minutes)

You already have Claude Code or Cursor. Then:

```bash
./scripts/install.sh
```

That copies `Marbles.app` to `/Applications` and launches it. First launch:

1. Merges `marbles-hook` into `~/.claude/settings.json` and `~/.cursor/hooks.json` (your other hooks stay).
2. Shows a confirmation with **Undo**.
3. Shows a **demo marble** only if this is the first launch and nothing in `~/.claude/projects` was active in the last two hours.

If macOS says the app can’t be opened, right-click `/Applications/Marbles.app` → **Open**.

Homebrew, after `./scripts/package.sh` and zipping `dist/Marbles.app` to `dist/Marbles.zip`:

```bash
brew install --cask --no-quarantine Casks/marbles.rb
```

## After install

- Menu bar extra → **Setup** — hooks and app detection.
- **Install / Repair Hooks** — idempotent; rewrites the helper path after an upgrade.
- **Undo Hooks** — removes only Marbles-owned entries.
- Restart any Claude Code session that was already open.

## Uninstall

```bash
./scripts/uninstall.sh
./scripts/uninstall.sh --purge   # also deletes ~/Library/Application Support/Marbles
```

## Contributor path

```bash
./scripts/test.sh
./scripts/dev-run.sh
```

Debug builds rewrite hook commands to the built helper.

## Jump in

Click a marble to go to its session. The hook helper runs inside the session's process tree, so it reports the terminal that owns it; Marbles then brings the exact tab forward:

| Host | How the tab is found |
| --- | --- |
| Ghostty | AppleScript dictionary: terminal matching the session cwd, with Claude's tab title breaking ties |
| Terminal.app, iTerm2 | AppleScript: tab / session whose `tty` matches |
| kitty, WezTerm | `kitten @ focus-window` (needs `allow_remote_control`), `wezterm cli activate-pane` |
| tmux | `select-window` / `select-pane` first, then the terminal hosting the attached client |
| Cursor, Conductor, Claude app, VS Code, anything else | The app is activated |

macOS asks once per host app for Automation permission ("Marbles wants to control Ghostty"). Sessions that predate the hooks fall back to opening Terminal in the session directory.
