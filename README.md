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

Debug builds rewrite hook commands to the built helper. Focus jump-in opens Claude Code, Cursor, Terminal, or Conductor.
