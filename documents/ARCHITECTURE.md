# Marbles — Architecture

**Status:** Draft for implementation handoff  
**Date:** 2026-08-23  
**Companion spec:** [PRD.md](PRD.md)  
**Visual north star:** [references/marble-visual-reference.png](references/marble-visual-reference.png)

This document is the implementation contract. Subagents should implement against it, not reinvent product decisions. If a change conflicts with the PRD, update the PRD first.

---

## 1. Purpose and how to use this doc

Marbles is a native macOS overlay: one always-on-top panel, one marble per local parent session (Claude Code or Cursor Agent), three interaction modes, hook-driven live status.

Use this document to:

- Pick a workstream (see §16) and stay inside that module boundary.
- Share types via the contracts in §8–§11 instead of inventing parallel models.
- Treat the **invariants** in §3 as testable rules, not suggestions.
- **Leave a runnable, look-at-able app after every workstream.** A stream is not done until the founder can launch Marbles and visually judge that slice (see §16.1). Dummy data and a Debug menu are first-class, not leftovers.

Do **not** introduce Electron, a browser dashboard, a cloud backend, accounts, or a second windowing system without an explicit PRD change.

---

## 2. System context

```text
┌─────────────┐  hooks (async, exit 0)   ┌──────────────────┐
│ Claude Code │ ───────────────────────► │ marbles-hook     │
│ CLI / app / │  stdin JSON              │ (tiny helper)    │
│ Conductor   │                          └────────┬─────────┘
└─────────────┘                                   │ POST JSON
                                                  ▼
                                         ┌──────────────────┐
 ~/.claude/projects/**/*.jsonl ────────► │ Marbles.app      │
 claude PIDs (process scan)    ────────► │  Overlay + Metal │
                                         │  AgentStore      │
                                         └────────┬─────────┘
                                                  │ jump-in
                    ┌──────────────┬──────────────┼──────────────┐
                    ▼              ▼              ▼              ▼
              Claude Code     Terminal.*     Conductor      (optional reply)
```

**Trust boundary:** everything stays on localhost / the user’s home directory. The hook helper is the only process Claude Code launches. It must be readable, fast, and unable to block a tool call.

**Non-goals inherited from the PRD:** spawn/kill agents, full transcripts, remote fleets, Windows/Linux.

---

## 3. Invariants (do not violate)

1. Cluster marble layout size = **36×36 pt**. Backing store may be 2×/3×.
2. Transparent pixels **click through**. The cluster must not own a large invisible rect.
3. Overlay stays above other apps and joins all Spaces (`fullScreenAuxiliary` where possible).
4. One **parent session** = one marble. Subagents are chips or satellites only. v1 never promotes a subagent to its own marble.
5. Interior family is **identity**, never status. Status is motion, chips, completion bloom, or the error hue filter.
6. Error / crash = **red hue filter** over the existing marble. No fractures, cracks, or error badges on the art.
7. Finished = **freeze + one-shot completion bloom**, visible at Cluster scale.
8. Hooks are `async` and **always exit 0**. Missing Marbles ⇒ no-op, agents keep working.
9. No telemetry. No upload of transcripts, prompts, or tool inputs.
10. Focus must not become a second Claude Code (no file tree, no full transcript, popover ≤360pt wide).
11. Reply composer ships only if delivery is proven. Otherwise show an honest fallback.
12. Install path for an engineer who already has Claude Code is **< 5 minutes**. Source builds are not that path.

---

## 4. Recommended repo layout

Target tree after M0. Do not scatter Swift across the repo root.

```text
marbles-v2/
  documents/
    PRD.md
    ARCHITECTURE.md
    references/marble-visual-reference.png
  apps/Marbles/                      # Xcode project + Swift sources
    Marbles.xcodeproj
    Sources/
      App/                           # @main, AppDelegate, menu bar
      Overlay/                       # NSPanel, click-through, Spaces
      Mode/                          # ModeController, transitions
      Layout/                        # Snap, lattice, line, safe area
      Agents/                        # AgentStore, models, discovery
      Ingest/                        # Local listener
      Identity/                      # seed → MarbleParams
      Render/                        # Metal renderer + hue filter
      Chips/                         # Icon chips / thinking glyph
      Focus/                         # Popover UI, preview, actions
      JumpIn/                        # Claude Code / Terminal / Conductor
      Hooks/                         # settings.json merge / repair / undo
      Persistence/                   # seeds, snap, prefs
      Demo/                          # first-run demo marble
    Resources/
      Shaders/
      Chips.xcassets
    Tests/                           # XCTest / Swift Testing
  tools/marbles-hook/
    main.swift
    Tests/
  scripts/
    install.sh
    uninstall.sh
  Tests/Fixtures/hooks/              # checked-in Claude stdin JSON (snake_case)
```

**Packaging:** `Marbles.app` embeds `marbles-hook` at `Contents/Helpers/marbles-hook`. The hook command in `~/.claude/settings.json` points at that absolute path (rewritten on update).

---

## 5. Process and thread model

| Process | Role | Lifetime |
| --- | --- | --- |
| `Marbles.app` | UI, Metal, AgentStore, ingest server, jump-in | Login item / user launched |
| `marbles-hook` | Read hook JSON from stdin, POST, exit | Milliseconds per event |

**Threads inside the app**

- **Main:** all AppKit / SwiftUI / window geometry / hit testing.
- **Ingest:** GCD serial or Swift actor `IngestServer` accepts sockets; hops to `AgentStore` via `MainActor`.
- **Discovery:** background `Task` for JSONL + `ps` scans; merge on main.
- **Render:** Metal command queue. Per-frame uniforms only; no file I/O on the draw path.

`AgentStore` is the single writer for agent state. Views observe it. Hooks never touch windows directly.

---

## 6. Module map

Each module has one owner. Cross-module calls go through the types in §8.

| Module | Responsibility | Must not |
| --- | --- | --- |
| **App** | Lifecycle, menu bar extra, first-run, permissions copy, **Debug menu** | Layout math, shaders |
| **Overlay** | `NSPanel` level, Spaces, click-through, display changes | Mode policy |
| **Mode** | Cluster ↔ Active ↔ Focus state machine + animation clocks | Know hook JSON |
| **Layout** | Snap points, isometric lattice, Active axis, Focus anchor, overflow | Render pixels |
| **Agents** | Session lifecycle, status derivation, overflow ranking | Draw or open apps |
| **Ingest** | Bind socket/HTTP, validate payload, ack 204 | Interpret UI |
| **Identity** | Deterministic `session_id` → `MarbleParams` | Animate status |
| **Render** | Draw marble + error hue + freeze + bloom uniforms | Hit-test policy |
| **Chips** | Tool → SF Symbol / custom glyph; trail length by mode | Session identity |
| **Focus** | Preview card, action buttons, reply field visibility | Hook install |
| **JumpIn** | Activate Claude Code / Terminal / Conductor; reply adapters | Change agent status |
| **Hooks** | Idempotent merge into `~/.claude/settings.json` | Network except localhost (n/a) |
| **Persistence** | Snap, seeds, prefs, launch-at-login | |
| **Demo** | Synthetic agent on first launch only, after a 2h discovery miss | Survive after a real session appears; reappear on later empty launches |

---

## 7. UI architecture

### 7.1 Windows

**Overlay panel (always)**

- `NSPanel`, **non-activating** in Cluster and Active.
- **Focus + reply:** briefly activate the app when the composer is shown *and* `ReplyDelivery.canReply` is true; deactivate on Focus exit. If the composer is hidden, stay non-activating.
- Level: **`NSWindow.Level.statusBar`**. If a specific full-screen app covers it, do not silently bump the level; file a bug and use the documented fallback “this Space only.”
- `collectionBehavior`: `[.canJoinAllSpaces, .fullScreenAuxiliary]`. **Do not set `.stationary`.**
- `NSApplication.activationPolicy = .accessory` (`LSUIElement` = true). No Dock tile. Menu bar extra is the app chrome.
- Size: **tight bounding box of visible marbles + chips + (in Focus) the popover**. Layout is the source of truth for the AABB each frame; Overlay resizes to it (inset 8pt).
- `ignoresMouseEvents` is **false**, but `hitTest` returns `nil` on fully transparent pixels (custom `OverlayView`).
- Hide overlay = `orderOut` + pause the Metal display link. Show = `orderFront` + resume.

**Menu bar extra**

- `NSStatusItem` (template or tiny marble).
- Menu: Show/Hide overlay, Preferences, Install/Repair hooks, **Debug** (W1+), About, Quit.
- `Cmd-H` must not hide Marbles, including when Marbles is key for the reply field. Provide explicit “Hide Marbles.” Set `NSApp.presentationOptions` / intercept hide as needed so accessory policy does not inherit document-app hide.

**Preferences**

- SwiftUI `Settings` scene or a small utility window. Fields per PRD §12.

No document windows. No Dock tile bouncing for ordinary tool calls. Completion may optionally post a `UNNotification` (off by default).

### 7.2 View tree

```text
OverlayPanel
  OverlayRootView            // hit-test pass-through
    ClusterOrLineLayer       // marble views at Layout positions
      MarbleView(id) × N     // Metal-backed NSView or SwiftUI representable
      ChipView × N
      OverflowMarble?        // +N
    FocusPopover?            // only in Focus; SwiftUI
```

Mode transitions animate `MarbleFrame` (center, size, z, dim) with an interruptible spring (**280ms** settle, damping ratio ~0.85). Layout publishes target frames; Mode interpolates. On interrupt, keep current visual frame as the new start; switch the target. Reduced motion: set frames immediately.

### 7.3 Mode state machine

```text
          click marble / chip / +N
  Cluster ─────────────────────────────────────► Active
     ▲                                            │
     │ Esc / click outside / drag-to-snap*        │ click marble
     └──────────────────────────────────────────  │
                                                  ▼
                                               Focus
                                                  │
          Esc / click outside / click hero ───────┘  → Active
          click other marble while focused          → Focus(other)
```

\* Starting a drag (≥4pt slop) **collapses to Cluster first**, then snaps. A click under 4pt of movement is a click, not a drag.

**Implementation type** (`Mode/`, not `Agents/`):

```swift
enum OverlayMode: Equatable {
  case cluster
  case active
  case focus(AgentID)
}
```

Rules:

- Cluster hit = union of marble circles + chip circles + overflow circle. Gaps pass through. Bloom-ring pixels outside the 36pt circle do **not** hit.
- Cluster click → `.active` (do not skip to Focus in v1).
- Fast Cluster → marble click must **interrupt** the unpack and land on `.focus`. Other marbles snap to their Active targets, then the non-hero dim (see §10.3 `dim`).
- `Esc` is handled at the panel. Focus `Esc` → Active. Active `Esc` → Cluster.
- Click the focused hero marble → Active. Click a different marble in Focus → switch Focus.
- Click outside the popover passes through and dismisses to Active.
- `OverlayMode` lives in Mode/. `Agent` types live in Agents/.

### 7.4 Placement and snap

**Snap targets (current display):**

- 4 corners + 4 edge midpoints.
- Release **always** snaps to the nearest of the 8 targets. `.free` is transient during an in-progress drag only — Cluster never rests off a snap point.
- Inset: `max(12, screen.auxiliaryTopLeftArea / safeArea)` plus Dock/Stage Manager visible frames. Do not hard-code 24pt.

**Persistence:** `SnapState` keyed by **`NSScreen.deviceDescription["NSScreenNumber"]` as UInt32** (stable enough; on miss, fall back to frame-size hash). Persisted value is always `.snap(SnapPoint)`.

On unplug: if the stored display is gone, move the cluster to the **main** screen’s same `SnapPoint`, or `.bottomRight` if missing.

**Active orientation** (from the locked snap point):

| Position | Line axis | Growth |
| --- | --- | --- |
| Left midpoint | vertical | inward (right) |
| Right midpoint | vertical | inward (left) |
| Bottom midpoint | horizontal | inward (up) |
| Top midpoint | horizontal | inward (down) |
| Any corner | **vertical** | inward along the nearest vertical edge |

Active overflow: **scroll along the line axis** (scroll-wheel / two-finger / drag on the line). No second rank in v1. Never clip without a way to reach every marble.

**Focus popover** opens toward screen interior, ≤360pt wide, never over the Notch.

**Multi-display:** cluster lives on the screen it was last dropped on (last-drop is the “which display” pref — no separate picker). Recalculate snap on `NSApplication.didChangeScreenParametersNotification`. Color space: **display-P3** drawables; error-hue red is authored in P3 so it matches across HDR/SDR.

---

## 8. Domain model

Canonical types live in `Agents/`. Other modules import them.

```swift
typealias AgentID = String          // Claude session_id; discovery fallback: "disc-" + hex(cwd + startedAt)

enum AgentStatus: Equatable {
  case working
  case thinking
  case waitingOnUser
  case finished
  case error
  case idle
}

enum Source: String, Codable {
  case cli, claudeApp, conductor, cursor, discovery, demo
}

struct ToolEvent: Equatable, Identifiable {
  var id: String
  var name: String
  var fileHint: String?
  var phase: Phase
  var at: Date
  enum Phase { case started, succeeded, failed }
}

struct SubagentRecord: Equatable, Identifiable {
  var id: String                    // hook agent_id
  var type: String?
  var startedAt: Date
}

struct Agent: Identifiable, Equatable {
  var id: AgentID
  var cwd: URL?
  var pid: Int32?
  var source: Source
  var conductorWorkspaceID: String?
  var status: AgentStatus
  var turnOpen: Bool
  var currentTool: ToolEvent?
  var recentTools: [ToolEvent]      // last 3, newest first
  var lastAssistantPreview: String?
  var subagents: [SubagentRecord]   // never their own marbles
  var startedAt: Date
  var lastEventAt: Date
  var sessionEndedAt: Date?
  var seed: UInt64
  var latticeIndex: Int?            // sticky 0...26
  var isDemo: Bool
  var animationTime: Float          // last shader time; never reset to 0
}

enum SnapPoint: String, Codable, CaseIterable {
  case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
}

enum SnapState: Codable {
  case snap(SnapPoint)
  case free(x: Double, y: Double)   // display-local points
}

struct OverflowToken: Equatable {
  var hiddenCount: Int              // agents.count - 26
}
```

**Status reducer** (`AgentStore.apply(_ event: HookEvent)`), highest flag wins after the event is applied:

| Event | Mutation |
| --- | --- |
| `SessionStart` | Upsert by `session_id`. `source` from payload `source` / `matcher`: `resume`/`compact` **revives** the same id (keep seed, latticeIndex, animationTime; clear currentTool; status `idle` until a prompt). `startup`/`fork`/`clear` = new turn history, same id if reused. |
| `UserPromptSubmit` | `turnOpen = true`, `status = thinking`, `sessionEndedAt = nil`, resume `animationTime` (do not zero). |
| `PreToolUse` | Set `currentTool` phase `started`; `status = working`. Extract summary per §11.4. |
| `PostToolUse` | Current tool → `succeeded`, push onto `recentTools`, clear `currentTool`; `status = thinking` if `turnOpen` else `finished`. |
| `PostToolUseFailure` | Same as post but phase `failed`. **Does not** set `error` (chip only). |
| `PermissionRequest` / needs-you `Notification` | `status = waitingOnUser`. |
| `Notification` `agent_completed` | Same as `Stop`. |
| `Stop` | `turnOpen = false`, `status = finished`, store preview, **start bloom** (skip if already `error`). |
| `StopFailure` | `turnOpen = false`, `status = error`, store preview, **no bloom**, ease `errorHue` on. |
| `SubagentStart` | Append `SubagentRecord`. If a `Task` tool is in flight for the same spawn, keep the satellite and drop the extra Task chip. |
| `SubagentStop` | Remove that id from `subagents`. |
| `SessionEnd` | `sessionEndedAt = now`. Reason ∈ {process crash, `error`, non-zero, `prompt_input_exit` after `StopFailure`} → `error`; else keep `finished` or set `finished`. Linger **45s** then fade 300ms and remove. |
| Process death (pid gone, `turnOpen`) | `status = error`. |
| `parseError` POST | Ignore (no agent). |

**Error dismiss:** Focus shows a “Dismiss” text button that removes the marble immediately if `sessionEndedAt != nil`, or clears `error` → `idle` if the process is still alive. No other dismiss control.

**Idle discovery cap:** at most **5** `discovery` agents, and only if mtime < **2 hours** *and* a matching `claude` PID exists. JSONL-only ghosts without a PID are not shown (prevents a 24h flood). Discovery never overwrites a hooked agent.

**Overflow:** if `agents.filter({ !$0.isDemo }).count > 27`, Cluster shows **26 sticky identity marbles + `OverflowToken`**. The token occupies lattice index **2** (`x:2, y:0, z:0`) — the rightmost cell on the front / top layer — not a side-floating badge. Evict from the Cluster *view* (do not delete) the occupant of that slot plus the non-focused agent(s) with oldest `lastEventAt` until 26 remain. Linger agents count. Overflow click → Active with the **full** list, same sticky order, scrollable.

**Slot assignment:** `latticeIndex` is assigned once: the lowest free index in `0...26` using traversal **front face first, then depth** — `(z, y, x)` with z=0 nearest the user. Do not sort-and-repack. `Identity.seed` = FNV-1a 64 of `session_id` UTF-8; persist as **hex string** in `seeds.json`. If `session_id` is missing, id = `"disc-" + hex(FNV(cwd + startedAt ISO8601))`.

---

## 9. Layout engine

`LayoutEngine.frames(agents:mode:snap:panelBounds:) -> [AgentID: MarbleFrame]`

```swift
struct MarbleFrame {
  var center: CGPoint               // panel coords
  var size: CGFloat                 // 36 cluster / 60 active / 72 focus hero
  var z: Int                        // isometric depth
  var dim: CGFloat                  // 0...1, 0.45 for non-hero in Focus
}
```

### 9.1 Cluster lattice

Isometric **packed** 3×3×3. Empty slots are not drawn.

Recommended integer coordinates `(x, y, z)` in `{0,1,2}³`, mapped with:

```text
screenX = origin.x + (x - y) * spacingX
screenY = origin.y + (x + y) * spacingY - z * spacingZ
```

Starting values (tune, then lock in tests): `spacingX = 20`, `spacingY = 17`, `spacingZ = 14` so 36pt spheres overlap. Cluster AABB must stay ≤ 140×130 pt for a full 26+N pile.

**Slot assignment:** use `Agent.latticeIndex` from §8. Do **not** re-pack by status or by sorting ids.

### 9.2 Active line

Place visible agents by ascending `latticeIndex` (then hidden/overflowed agents after, for the full list). Size **60pt**. **No** permanent captions. Hover (Active only): chip + one-line status using the Focus copy table (§12.1).

### 9.3 Hit testing

Each marble’s hit region is a **circle** of `size/2`, plus chip circles, plus the overflow circle. Lattice gaps are pass-through. Hit tests the **interpolated visual** center/size this frame, not the animation target.

Drag vs click: movement ≥ **4pt** before mouse-up is a drag.

---

## 10. Rendering architecture

### 10.1 Why Metal

Reference quality at 36pt needs a glass shell, frost, interior volume, specular, and a cheap post hue shift. One `MTKView` (or a single view with instanced draws) is enough for ≤27 spheres.

SceneKit is an acceptable prototype in M0–M1 **only if** the uniform contract below is preserved so M2 can swap the renderer.

**Not allowed for v1 pixels:** pre-rendered PNG sprite sheets as the identity, CSS/WebGL in a WKWebView.

### 10.2 Identity → uniforms

`Identity.params(seed: UInt64) -> MarbleParams` is pure and deterministic.

```swift
struct MarbleParams: Equatable {
  var family: InteriorFamily        // silk, crystal, prism, nebula, landscape, core
  var hue: Float                    // identity hue, 0...1
  var saturation: Float
  var frost: Float
  var inclusionDensity: Float
  var luminosity: Float
  var secondaryHue: Float
  var noiseOffset: SIMD3<Float>
}

enum InteriorFamily: UInt8, CaseIterable {
  case silk, crystal, prism, nebula, landscape, core
}
```

Family table (deterministic): let `r = seed % 100`. `0-21` silk, `22-42` crystal, `43-60` prism, `61-78` nebula, `79-88` core, `89-99` landscape. Same `session_id` ⇒ same params across relaunch (`seeds.json` hex).

### 10.3 Frame uniforms (status, not identity)

```swift
struct MarbleFrameUniforms {
  var time: Float                   // Agent.animationTime; HOLD last value when frozen/waiting
  var advection: Float              // working 1, thinking 0.35, else 0
  var pulse: Float                  // thinking only
  var freeze: Float                 // 1 = finished or error photograph
  var hold: Float                   // 1 = waitingOnUser (advection 0, freeze 0 — mid-swirl hold)
  var errorHue: Float               // 0...1, ease on 250ms, ease off 250ms on recover
  var bloom: Float                  // 0...1 one-shot completion (caustic sweep, 400–700ms)
  var attention: Float              // waitingOnUser; 0 if reduced motion
  var dim: Float                    // Focus non-hero
  var rimBoost: Float               // 0.15 settled finished rest (with check chip)
}
```

**Time:** Mode/W3 advances `animationTime` only while `status == working || thinking`. Finished, error, waiting, idle: **hold** the last `time`. A new `UserPromptSubmit` continues from that value. **Never assign 0** on freeze.

**Error hue:** post-shade hue-rotate toward red, keep luminance. Not a family swap. `StopFailure` / process death: error hue **instead of** bloom.

**Reduced motion:** if pref **or** `NSWorkspace.accessibilityDisplayShouldReduceMotion`: `advection = 0`, `attention = 0`, layout **snaps** (no 240–320ms spring). Still allow `freeze`, `errorHue`, `bloom`, chips.

**Completion:** one look — **caustic sweep**. Stagger 80–120ms; cap **4** concurrent blooms, queue the rest. Settled rest = `rimBoost` + check chip until next `UserPromptSubmit` (no manual dismiss for the check).

**Metal lifetime:** one `MTKView`, instanced draws, device/queue/pipelines owned by Render. Pause display link when overlay is hidden **or** every marble has `advection==0 && bloom==0 && attention==0 && errorHue` is settled. Color space display-P3. Same shader at 36 / 60 / 72pt; no extra landscape micro-detail below 60pt.

**Desktop bleed:** optional faint backdrop blur *behind* the cluster (private API-free: a small `NSVisualEffectView` clipped to a rounded union, very low material). Never a black plate.

**Light/dark:** rim light + specular must keep a pale marble visible on a white Google Doc.

### 10.4 Chips

Drawn in AppKit/SwiftUI *above* the Metal view so icons stay sharp.

| Mode | Chips |
| --- | --- |
| Cluster | Exactly one: failed current tool → fault mark; else current tool; else thinking; else waiting; else finished check; else none (idle/error uses hue, no chip) |
| Active | Live + last 2 faded (fade 2s) |
| Focus | Recent-activity row (text allowed) |

Map via `Chips.symbol(for:)`:

| `name` | SF Symbol |
| --- | --- |
| thinking | `ellipsis.circle` |
| Read | `doc.text` |
| Write / Edit / NotebookEdit | `pencil` |
| Bash / Shell | `apple.terminal` |
| Grep / Glob | `magnifyingglass` |
| WebSearch / WebFetch | `globe` |
| Task | `arrow.triangle.branch` (omit if a satellite exists) |
| `mcp__*` | `powerplug` + server token = second path segment, Focus only |
| git | `arrow.triangle.branch` if Bash `command` prefix is `git` (after optional path) |
| permission | `questionmark.circle` |
| finished | `checkmark.circle` |
| tool fail | `exclamationmark.circle` |

Chip sits on the **lower-right rim** in screen space (does not orbit). Satellites (if pref on): up to 3 dots, 8pt, 14pt outside the rim, inherit parent identity hue, no extra motion when reduced-motion.

Chip size ~8–10pt on the rim at cluster scale. Thinking glyph ≠ tool glyph.

---

## 11. Ingest contract

### 11.1 Transport

**v1 default:** HTTP `POST http://127.0.0.1:17832/hook`  
Fallback if bind fails: increment port and rewrite helper args via a small file:

`~/Library/Application Support/Marbles/ingest.json` → `{ "url": "http://127.0.0.1:17833/hook" }`

Unix socket is a fine v1.1 swap; keep the JSON body identical.

**Response:** `204` empty. Helper treats connection-refused as success (exit 0). Timeout ≤150ms.

### 11.2 Helper

`marbles-hook` is **source-agnostic**:

1. Read stdin to EOF (Claude or Cursor JSON).
2. Optionally read `ingest.json` for URL.
3. POST body = stdin bytes, header `Content-Type: application/json`, `X-Marbles-Hook: 1`.
4. Exit 0 in all cases (including malformed stdin — still exit 0, optionally POST a `{ "parseError": true }`).

Never print to stdout (Claude may attach it on some events; Cursor may treat stdout as a hook response and loop). Log to `~/Library/Logs/Marbles/hook.log` only if `MARBLES_HOOK_DEBUG=1`.

On Cursor, also return `{}` or no stdout so we never send `followup_message` / permission decisions. Observation only. `failClosed` must be **false** on every Cursor entry we write.

### 11.3 Hook coverage

Installer writes **two** configs. Same helper path.

**Claude Code** — merge into `~/.claude/settings.json` under a Marbles-owned block. Events:

`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `PermissionRequest`

All `async: true` (or current Claude equivalent). `command` = quoted path to `Contents/Helpers/marbles-hook`.

**Cursor** — merge into **`~/.cursor/hooks.json`** (user-level, so every workspace’s agents show up). Native Cursor schema (`version: 1`), not Claude’s nested format. Do **not** depend on Cursor’s “Third-party skills” loader for `~/.claude/settings.json`.

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [{ "command": "/Applications/Marbles.app/Contents/Helpers/marbles-hook" }],
    "sessionEnd": [{ "command": "…" }],
    "beforeSubmitPrompt": [{ "command": "…" }],
    "preToolUse": [{ "command": "…" }],
    "postToolUse": [{ "command": "…" }],
    "postToolUseFailure": [{ "command": "…" }],
    "stop": [{ "command": "…" }],
    "subagentStart": [{ "command": "…" }],
    "subagentStop": [{ "command": "…" }],
    "afterAgentThought": [{ "command": "…" }],
    "afterAgentResponse": [{ "command": "…" }]
  }
}
```

No `failClosed`. No Tab hooks. No `workspaceOpen`. Cursor watches this file and reloads; still tell the user to start a **new Agent chat** if an already-open session is silent.

**Merge rules (both files)**

- Idempotent. Second install is a no-op.
- Do not delete hooks Marbles did not write.
- Repair replaces only Marbles-owned entries (`command` contains `marbles-hook`).
- Undo removes only Marbles-owned entries.

### 11.4 Normalized event

Ingest decodes Claude stdin with `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` (helper POSTs **raw** stdin; the app owns mapping). Unknown fields ignored. Fixtures: `Tests/Fixtures/hooks/*.json`.

| Claude stdin | `HookEvent` | Notes |
| --- | --- | --- |
| `hook_event_name` | `hookEventName` | Dispatch |
| `session_id` or Cursor `conversation_id` | `sessionID` | Required; drop event if both missing |
| `cwd` | `cwd` | Jump-in, Conductor detect |
| `transcript_path` | `transcriptPath` | Dedupe vs jsonl only; do not read body on the hot path |
| `tool_name` | `toolName` | Chips |
| `tool_input` | `toolInputSummary` | Extract only: Read/Edit/Write → basename of `file_path`; Bash/Shell → first 40 chars of `command`; else omit. Max **80** chars. Never persist the object. |
| `last_assistant_message` | `lastAssistantMessage` | Trust on `Stop` / `StopFailure` / `SubagentStop` only |
| `notification_type` or `type` | `notificationType` | See Claude Notification matchers |
| `agent_id` / `agent_type` | `agentID` / `agentType` | Subagents |
| `reason` / `source` | `sessionEndReason` / `sessionStartSource` | `startup`, `resume`, `clear`, `compact`, `fork`; end: `clear`, `resume`, `logout`, `prompt_input_exit`, `other` |
| `tool_response` | — | Dropped. Failure = `PostToolUseFailure` event |

```swift
struct HookEvent: Codable {
  var hookEventName: String
  var sessionID: String
  var cwd: String?
  var transcriptPath: String?
  var toolName: String?
  var toolInputSummary: String?
  var lastAssistantMessage: String?
  var notificationType: String?
  var agentID: String?
  var agentType: String?
  var sessionEndReason: String?
  var sessionStartSource: String?
  var composerMode: String?         // Cursor: agent | ask | edit
  var isBackgroundAgent: Bool?
  var stopStatus: String?           // Cursor stop: completed | aborted | error
  var sourceHint: Source?           // set by mapper
}
```

**Preview text:** memory only, max 280 characters. Never persist `user_email`.

### 11.4.1 Cursor event map

Ingest detects Cursor payloads by `hook_event_name` camelCase (`sessionStart`, `preToolUse`, …) or presence of `conversation_id` + `cursor_version`.

| Cursor event | Treat as | Notes |
| --- | --- | --- |
| `sessionStart` | `SessionStart` | `session_id` == `conversation_id`. **Drop** if `composer_mode` is `ask` or `edit`. Keep `agent` and `is_background_agent == true`. |
| `sessionEnd` | `SessionEnd` | |
| `beforeSubmitPrompt` | `UserPromptSubmit` | |
| `preToolUse` / `postToolUse` / `postToolUseFailure` | same | Map tool names: `Shell`→Bash chip, `Write` covers Edit. Cursor `MCP: foo` → mcp chip. |
| `afterAgentThought` | thinking | `status = thinking` if `turnOpen` and no current tool. Do not store `text`. |
| `afterAgentResponse` | preview | First 280 chars of `text` → `lastAssistantPreview`. |
| `stop` | `Stop` or `StopFailure` | `status == error` → error (no bloom). `completed` / `aborted` → finished + bloom. |
| `subagentStart` / `subagentStop` | same | |
| Tab / `workspaceOpen` | ignore | Helper may still POST; Ingest drops. |

**Needs-you:** Cursor has no `Notification` / `PermissionRequest`. Waiting-on-user will rarely fire for Cursor agents unless we later infer it from a permission UI we cannot see.

**Do not** enable Cursor third-party loading of Claude hooks as the only path — dual-write `~/.cursor/hooks.json`.

**JSONC merge:** `Hooks` must parse `~/.claude/settings.json` as JSON-with-comments (strip `//` and `/* */` outside strings, then JSON). Write-back **preserves** comments by patching only Marbles-owned hook objects (match `command` contains `marbles-hook`). If the file is invalid, **do not overwrite**; surface Repair error. If the file is missing, write a minimal valid JSON with only Marbles hooks.

Claude may not hot-reload hooks. First-run copy: “Restart any already-open Claude Code session to connect it.” New sessions pick up hooks immediately.

### 11.5 Discovery (secondary)

On launch, then every 5s until at least one hooked agent exists, then every 30s:

1. List `~/.claude/projects/*/*.jsonl` (encoded cwd folder + `session_id.jsonl`).
2. Attach `pid` via `ps` / `proc_pidinfo` for processes named `claude` (and `Claude` helper if needed).
3. Cursor live agents are **hook-only** in v1 (no jsonl scan of `~/.cursor/projects/**/agent-transcripts`). Discovery cap still applies to Claude ghosts.
4. Create a discovery agent only per §8 idle cap (PID + 2h).

Dedup: same `session_id` or same (cwd + pid). PID reuse: if `pid` start time (or `lstart`) does not match `startedAt` ±2s, detach.

**Conductor cwd:** `~/conductor/workspaces/<project>/<workspace>/` (tilde-expanded). `conductorWorkspaceID` = last path component. Bundle id: `build.conductor.desktop` (confirm at W6; if wrong, update this line only).

---

## 12. Jump-in and reply

### 12.1 Focus copy and chrome

Button order, left to right: **Open Claude Code** (hidden if `source == cursor`) · **Open Cursor** (shown if `source == cursor`; bundle `com.todesktop.*` / `com.cursor` — W6 confirms and updates this line) · **Open Terminal** · **Open Conductor** (hidden if `canOpen == false`) · reply composer or the fallback sentence.

Cursor jump-in: activate the Cursor app and, if possible, the workspace in `workspace_roots[0]`. Session-level focus is stretch.

Disabled (not hidden) when the app is missing or `cwd`/`pid` is nil, with tooltip: “Claude Code isn’t installed”, “No working directory”, “Can’t find this terminal”.

Preview line: PRD precedence (waiting → tool → assistant → status word). Max 3 lines, 280 chars, 13pt.

Return does not jump-in. Esc always dismisses Focus.

### 12.2 Adapters

`JumpIn` is a protocol + three adapters. Focus never shells out itself.

```swift
protocol JumpTarget {
  func canOpen(_ agent: Agent) -> Bool
  func open(_ agent: Agent) async throws
}

protocol ReplyDelivery {
  func canReply(_ agent: Agent) -> Bool
  func reply(_ agent: Agent, text: String) async throws
}
```

| Target | Bundle ID (v1 lock; fix here if wrong) | Open |
| --- | --- | --- |
| Marbles | `dev.marbles.app` | — |
| Claude Code app | `com.anthropic.claude-code` | `NSWorkspace` activate; session-level if a URL scheme exists; else cwd fallback |
| Terminal.app | `com.apple.Terminal` | |
| iTerm2 | `com.googlecode.iterm2` | |
| Ghostty | `com.mitchellh.ghostty` | |
| kitty | `net.kovidgoyal.kitty` | |
| Warp | `dev.warp.Warp-Stable` | |
| Conductor | `build.conductor.desktop` | Hide button if cwd is not a Conductor workspace |

Terminal resolution: `pid` → TTY → emulator. Multiple TTYs with the same cwd: pick the one whose pid matches, else the most recently fronted window, else `open -a Terminal <cwd>`.

**Bar for M3:** correct *app* ≥90%. Correct tab is stretch.

**Reply:** official Claude IPC → Conductor local/auth path. **No keystroke injection.** Composer max 500 chars. Send allowed while `working` (steers the turn if the API does). On throw, keep the text and show “Couldn’t deliver — try opening Claude Code.”

Accessibility / Automation / Notifications prompt on first use of that feature, not before the first marble.

---

## 13. Persistence

Directory: `~/Library/Application Support/Marbles/`

| File | Contents |
| --- | --- |
| `prefs.json` | `{ "version": 1, "reducedMotion": false, "completionSound": false, "satellites": true, "launchAtLogin": false, "overlayHidden": false }` |
| `snap.json` | `{ "version": 1, "displays": { "<screenNumber>": { "snap": "bottomRight" } } }` |
| `seeds.json` | `{ "version": 1, "seeds": { "<session_id>": "<hex u64>" } }` |
| `ingest.json` | `{ "url": "http://127.0.0.1:17832/hook" }` |

No transcript cache. Previews, cwd, pid, tool names live in memory only. `MARBLES_HOOK_DEBUG` logs are truncated to 2 KB/line, no stdin body, deleted after 24h.

Port constant: `Agents/IngestConstants.swift` `static let defaultPort = 17832`. Helper always re-reads `ingest.json`. On upgrade, app rewrites the hook command path and `ingest.json`.

---

## 14. Installation architecture

**Engineer path (M4):** Homebrew cask *or* `scripts/install.sh` that:

1. Copies `Marbles.app` → `/Applications`
2. Opens it
3. App runs `Hooks.install()` and shows confirmation + undo
4. Demo marble only per §6 Demo rules
5. Defers TCC prompts

**Contributor path:** open `apps/Marbles/Marbles.xcodeproj`, run the Marbles scheme (embeds helper). On each debug launch, rewrite the hook command to the built helper path.

**Uninstall:** remove app + Marbles-owned hooks. Offer to delete Application Support (default **no**).

**Signing:** Developer ID + notarization. **Do not sandbox** the app. Entitlements: `com.apple.security.automation.apple-events` = true; hardened runtime on app **and** `Contents/Helpers/marbles-hook`. Universal binary (arm64 + x86_64) if we still care about Intel; otherwise arm64-only is fine and must be stated in install docs.

Until notarized: README step “Open anyway” (right-click) — still part of the 5-minute path.

**First-run checklist** (menu-bar extra popover, not a wizard): Hooks installed / missing / error (Claude **and** Cursor files) · Claude Code detected · Cursor detected · Conductor detected · “Start a Claude Code or Cursor Agent session to see a live marble.” Demo Focus is allowed; jump-in buttons disabled; label the preview “Demo.”

---

## 15. Testing strategy

| Layer | What |
| --- | --- |
| `LayoutTests` | 8 snap orientations; corner → vertical; 36pt cluster / 60pt Active; sticky slots; 27 vs 28 overflow; linger counts. Run `./scripts/test.sh`. |
| `StatusTests` | reducer table in §8; error vs finished vs waiting vs PostToolUseFailure |
| `IdentityTests` | same seed ⇒ same params; family table over 100 seeds |
| `HookContractTests` | helper exits 0 on refused connection and bad JSON; fixtures decode |
| `HooksMergeTests` | idempotent merge / undo; JSONC comments survive |
| `MotionTests` | freeze holds `animationTime`; waiting uses `hold` not `freeze`; error skips bloom |
| UI | click-through gaps; bloom ring not hittable; light desktop rim; error hue |

A headless “fake ingest” debug menu should inject working / thinking / finished / error agents without Claude Code.

---

## 16. Workstreams for parallel subagents

Hand one stream to one agent. Land against `main` via small PRs. Do not rewrite another stream’s types — extend `Agents/` models if needed.

**A workstream is not done until the founder can launch the app and visually judge that slice.** Unit tests are not a substitute. Each stream ships a runnable Marbles (W4 may also ship a standalone `MarblePreview` target) plus the Debug items below.

### 16.1 Manual test gate (required)

From W1 on, the menu bar **Debug** submenu (DEBUG / `#if DEBUG` builds only) must include:

| Command | What it does |
| --- | --- |
| Inject 3 dummy agents | Distinct seeds, mixed statuses |
| Inject 9 / 27 / 28 agents | Lattice depth + overflow `+N` |
| Set selected → Working / Thinking / Waiting / Finished / Error | Drive uniforms live |
| Fire completion bloom | One-shot even if already finished |
| Cycle current tool | Read → Edit → Bash/Shell → Grep → Task |
| Clear all injected | Leaves real hooked agents |
| Replay fixture… | POST a file from `Tests/Fixtures/hooks/` into Ingest |

Debug injections use `source = .demo` (or a `debug-` id prefix) so they never collide with live `session_id`s.

Founder look-path after every stream (put this in the PR description):

| ID | Stream | First slice | Depends on | You should be able to look at |
| --- | --- | --- | --- | --- |
| **W0** | Overlay panel + click-through | Empty floating panel, menu bar, pass-through hits | — | A small empty panel over Safari/Slack. Clicks on empty glass hit the app beneath. Drag the panel. Menu bar extra works. |
| **W1** | Mode + Layout + snap | Dummy 3 agents; Cluster/Active/Focus; 8 snap points | W0 | Placeholders in a pile. Click pile → line. Click one → Focus card (can be ugly). Drag to all 8 snaps; corners expand **vertical**. Gaps click through. |
| **W2** | AgentStore + Ingest + helper | Fake + live events update status | W0 | Debug inject changes status. `curl` a fixture at `:17832/hook` updates a marble. Optional: install hooks and run a real Claude **or** Cursor Agent turn and watch a marble appear. |
| **W3** | Chips + motion + bloom + error hue | Works against dummy *or* live store | W1, W2 | Working swirls (even with placeholder spheres). Finished freezes + caustic sweep. Error goes **red** without cracks. Thinking vs tool chips readable at 36pt. |
| **W4** | Metal + Identity | Reference look at 36pt | W1 | Six families vs [the still](references/marble-visual-reference.png). Same marble on a white Google Doc **and** a dark desktop. Debug cycle seeds. No black plate. |
| **W5** | Focus popover + preview | Actions disabled until W6 | W1, W2 | Preview copy order (waiting / tool / text). Click hero to leave. Click another marble to switch. Card stays on-screen at every snap. |
| **W6** | Jump-in adapters | Claude Code / Cursor / Terminal / Conductor | W5 | Each visible button opens the right **app**. Cursor-sourced marbles show Open Cursor, not Claude Code. |
| **W7** | Hook installer + demo + prefs | Repair / undo both configs | W2 | First-run checklist. Demo marble if empty. Confirm `~/.claude/settings.json` **and** `~/.cursor/hooks.json` contain `marbles-hook`. Undo removes only ours. Reduced motion snaps. |
| **W8** | Packaging | cask / install.sh / notarize | W7 | Clean machine / other account: install in <5 min, see a marble. |

Suggested pairing: **W0→W1** and **W0→W2** in parallel after the panel exists; **W4** can prototype in a standalone MTKView **as long as that target is launchable for visual review**.

---

## 17. Milestone mapping

| Milestone | Streams | Done when |
| --- | --- | --- |
| **M0 Skeleton** | W0, W1 | Drag, snap, three dummy marbles, three modes |
| **M1 Live agents** | W2, W3, W7 **hook merge only** | Real Claude **or** Cursor sessions; working/freeze/error hue; chips; bloom |
| **M2 Material** | W4 | Procedural glass at reference quality; 6 families |
| **M3 Jump-in** | W5, W6 | Preview + three open actions; honest reply |
| **M4 Install** | W7 finish (demo, checklist, prefs), W8 | <5 min engineer path |

---

## 18. Decisions already made

| Decision | Choice | Why |
| --- | --- | --- |
| Stack | Native Swift / AppKit / SwiftUI / Metal | Overlay + glass; PRD rejects Electron |
| Cluster click | Occupied circles → Active | Click-through gaps; do not skip to Focus |
| Corner Active | Vertical line | PRD §7.2 |
| Error art | Red hue filter, no bloom | Keep identity; no fractures |
| Subagents | Chips / satellites only | Protect 3×3×3 |
| Lattice | Sticky index, packed isometric | Same marble stays put |
| Overflow | 26 + `+N` in lattice slot `(2,0,0)`; evict oldest `lastEventAt` | 27 slots, one used by overflow |
| Freeze time | Hold last `animationTime` | Resume from pose |
| Waiting | `hold=1`, not `freeze` | Mid-swirl, not “done” |
| Window | `.accessory` + `statusBar` + join-all | No Dock; no `.stationary` |
| Ingest | Local HTTP :17832 + helper | Simple hook `command` |
| Reply | No keystroke injection | Safety |
| Cursor agents | Native `~/.cursor/hooks.json`, same helper | Parallel API; don’t rely on third-party Claude import |
| Cmd+K / Ask / Tab | Ignored | Avoid a marble per inline edit |
| Manual test | Debug menu + look-gate per workstream | Founder judges pixels, not just tests |
| Demo marble | First launch + 2h discovery miss | Don’t refill an empty later day |
| Snap display | Last-drop | No extra pref |
| Tests | Inside the Xcode targets + `Tests/Fixtures/hooks` | One owner |

---

## 19. TCC, entitlements, and copy

| Capability | When prompted | Info.plist / notes |
| --- | --- | --- |
| Notifications | First time completion notifications are enabled | `NSUserNotificationsUsageDescription` if required: “Marbles can notify you when an agent finishes.” Off by default. Tap opens Focus for that agent. |
| Automation (Apple Events) | First jump-in to Terminal / iTerm / Conductor | `NSAppleEventsUsageDescription`: “Marbles brings the matching Terminal or Conductor window forward.” |
| Accessibility | Only if a jump-in adapter cannot succeed without it | `NSAccessibilityUsageDescription`: “Marbles uses Accessibility only to focus the terminal tab that belongs to this agent.” |
| Files | None extra if we stay in the home folder via POSIX | Do not ask for Full Disk Access. If `~/.claude` is unreadable, first-run shows “Can’t read Claude sessions.” |
| Local network | If macOS prompts for 127.0.0.1 | `NSLocalNetworkUsageDescription`: “Marbles receives local status from Claude Code hooks on this Mac.” |
| Sandbox | **Off** | Sandbox would break hooks and jump-in. |

Do not request TCC before a marble is on screen.

---

## 20. Open implementation risks

1. **Window level vs. full-screen / Stage Manager** — needs device testing; may require a fallback “always on this Space only.”
2. **Non-activating panel vs. Focus reply field** — may need a short activation on Focus.
3. **Claude Code session-level activation** — undocumented; JumpIn must degrade gracefully.
4. **Hook schema drift** — pin a fixture corpus of real payloads; treat unknown fields as ignored.
5. **Metal + many displays / HDR** — keep color space sRGB/display-p3 consistent so hue-filter red is the same red on every screen.
6. **Notch / safe area** — Layout must read `auxiliaryTopLeftArea` (or current AppKit equivalent), not hard-code 24pt.

---

## 21. Glossary (implementation)

| Term | Meaning |
| --- | --- |
| AgentStore | Single source of truth for `[Agent]` |
| MarbleParams | Identity uniforms (seeded, stable) |
| MarbleFrameUniforms | Status uniforms (motion, freeze, errorHue, bloom) |
| Packed lattice | Isometric 3×3×3 without drawing empty cells |
| Overflow marble | `+N` stand-in occupying one of 27 slots when count > 27 |
| Sticky slot | `session_id` → `latticeIndex` that does not shift when neighbors leave |
| hold vs freeze | Waiting holds the swirl (`hold`); finished/error is a photograph (`freeze`) |
| Marbles-owned hook | settings.json entry whose command path contains `marbles-hook` |
