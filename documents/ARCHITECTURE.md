# Marbles — Architecture

**Status:** Draft for implementation handoff  
**Date:** 2026-08-23  
**Companion spec:** [PRD.md](PRD.md)  
**Visual north star:** Paper Shaders [gem-smoke](https://github.com/paper-design/shaders/blob/main/packages/shaders/src/shaders/gem-smoke.ts) interiors in opaque 36pt discs.

This document is the implementation contract. Subagents should implement against it, not reinvent product decisions. If a change conflicts with the PRD, update the PRD first.

---

## 1. Purpose and how to use this doc

Marbles is a native macOS overlay: one always-on-top panel, one marble per local parent session (Claude Code or Cursor Agent), two interaction modes (Default dock / Focus), hook-driven live status.

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
                    ┌──────────────┬──────────────┬──────────────┐
                    ▼              ▼              ▼              ▼
              Claude Code       Cursor       Terminal.*      Conductor
```

**Trust boundary:** everything stays on localhost / the user’s home directory. The hook helper is the only process Claude Code launches. It must be readable, fast, and unable to block a tool call.

Ingest is **not** an open localhost API. `POST /hook` requires a per-machine token stored in `ingest.json` (mode `0600`) and sent as `X-Marbles-Token`. That stops drive-by `curl` and browser-to-localhost posts. A process that can read the user’s Application Support can still impersonate the helper — same-user malware is out of scope. Preview text from hooks is untrusted UI copy (capped, never HTML).

**Non-goals inherited from the PRD:** spawn/kill agents, full transcripts, remote fleets, Windows/Linux.

---

## 3. Invariants (do not violate)

1. Default and Focus marble layout size = **36×36 pt**. Backing store may be 2×/3×.
2. Transparent pixels **outside the dock pill** click through. The pill itself is opaque glass.
3. Overlay stays above other apps and joins all Spaces (`fullScreenAuxiliary` where possible).
4. One **parent session** = one marble. Subagents are chips or satellites only. v1 never promotes a subagent to its own marble.
5. Gem-smoke **palette** is identity, never status. Status is motion speed and the 3-light matrix (orb bloom / error hue are later chrome).
6. Error / crash = **red hue filter** over the existing marble. No fractures, cracks, or error badges on the art.
7. Finished = **freeze + one-shot completion bloom**, visible at Default dock scale.
8. Hooks are `async` and **always exit 0**. Missing Marbles ⇒ no-op, agents keep working.
9. No telemetry. No upload of transcripts, prompts, or tool inputs.
10. Focus must not become a second Claude Code (no file tree, no full transcript, popover ≤360pt wide).
11. Jump-in opens the matching app. Session/tab targeting is best-effort; never open `claude://code/new` (that starts a different session).
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
      Layout/                        # Snap, dock line, safe area
      Agents/                        # AgentStore, models, discovery
      Ingest/                        # Local listener
      Identity/                      # seed → MarbleParams
      Render/                        # Metal renderer + hue filter
      Chips/                         # 3-light matrix
      Focus/                         # Popover UI, preview, actions
      JumpIn/                        # Claude Code / Cursor / Terminal / Conductor
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
| **Mode** | Dock ↔ Focus state machine + animation clocks | Know hook JSON |
| **Layout** | Snap points, pill dock, Focus anchor, scroll | Render pixels |
| **Agents** | Session lifecycle, status derivation, overflow ranking | Draw or open apps |
| **Ingest** | Bind socket/HTTP, validate payload, ack 204 | Interpret UI |
| **Identity** | Deterministic `session_id` → `MarbleParams` | Animate status |
| **Render** | Draw gem-smoke discs from identity + time uniforms | Hit-test policy |
| **Chips** | 3-light matrix from status / current tool | Session identity |
| **Focus** | Preview card, action buttons | Hook install |
| **JumpIn** | Activate Claude Code / Cursor / Terminal / Conductor | Change agent status |
| **Hooks** | Idempotent merge into `~/.claude/settings.json` | Network except localhost (n/a) |
| **Persistence** | Snap, seeds, prefs, launch-at-login | |
| **Demo** | Synthetic agent on first launch only, after a 2h discovery miss | Survive after a real session appears; reappear on later empty launches |

---

## 7. UI architecture

### 7.1 Windows

**Overlay panel (always)**

- `NSPanel`, **non-activating** in Default. Focus may become key so Esc works. No reply field.
- Level: **`NSWindow.Level.statusBar`**. If a specific full-screen app covers it, do not silently bump the level; file a bug and use the documented fallback “this Space only.”
- `collectionBehavior`: `[.canJoinAllSpaces, .fullScreenAuxiliary]`. **Do not set `.stationary`.**
- `NSApplication.activationPolicy = .accessory` (`LSUIElement` = true). No Dock tile. Menu bar extra is the app chrome.
- Size: **tight bounding box of the dock pill + (in Focus) the popover**. Layout is the source of truth for the AABB each frame; Overlay resizes to it. The **dock** stays pinned to the snap midpoint; the card may extend the panel inward.
- `ignoresMouseEvents` is **false**, but `hitTest` returns `nil` on fully transparent pixels (custom `OverlayView`).
- Hide overlay = `orderOut` + pause the Metal display link. Show = `orderFront` + resume.

**Menu bar extra**

- `NSStatusItem` (template or tiny marble).
- Menu: Show/Hide overlay, Preferences, Install/Repair hooks, **Debug** (W1+), About, Quit.
- `Cmd-H` must not hide Marbles. Provide explicit “Hide Marbles.” Set `NSApp.presentationOptions` / intercept hide as needed so accessory policy does not inherit document-app hide.

**Preferences**

- SwiftUI `Settings` scene or a small utility window. Fields per PRD §12.

No document windows. No Dock tile bouncing for ordinary tool calls. Completion may optionally post a `UNNotification` (off by default).

### 7.2 View tree

```text
OverlayPanel
  OverlayRootView            // hit-test pass-through outside pill+card
    DockGlass                // NSGlassEffectView, stadium
    DockContent                  // marbles clipped to the pill
      MarbleView(id) × N     // Metal-backed NSView or SwiftUI representable
      IndicatorLightsView × N
    FocusPopover?            // only in Focus; SwiftUI
```

Mode transitions animate `MarbleFrame` (center, size, z) with an interruptible spring (**280ms** settle, damping ratio ~0.85). Layout publishes target frames; Mode interpolates. On interrupt, keep current visual frame as the new start; switch the target. Reduced motion: set frames immediately. No dimming.

### 7.3 Mode state machine

```text
          hover marble
  Dock ────────────────────────────────────────► Focus
     ▲                                            │
     │ Esc / click outside / hover off / dock glass │ hover or click other marble
     └──────────────────────────────────────────  │
                                                  ▼
                                               Focus(other)
```

\* Starting a drag (≥4pt slop) is **Default-only**. Focus does not drag; dock glass dismisses to Default instead. A click under 4pt of movement is a click, not a drag.

**Implementation type** (`Mode/`, not `Agents/`):

```swift
enum OverlayMode: Equatable {
  case dock
  case focus(AgentID)
}
```

Rules:

- Dock hit = stadium of the glass pill (marbles + chrome). Outside the pill passes through in Default.
- Hover a marble in Default → `.focus`. Hover another marble → switch Focus. Hovering the hero, the card, or dock chrome keeps Focus. Hovering off the pill and card → Default.
- Click a marble → `.focus` that agent (does not dismiss the hero).
- Click dock glass in Focus → Default (no drag). Click outside the overlay → Default.
- `Esc` is handled at the panel. Focus `Esc` → Default. Default `Esc` is a no-op.
- `OverlayMode` lives in Mode/. `Agent` types live in Agents/.

### 7.4 Placement and snap

**Snap targets (current display):**

- 4 edge midpoints only (`top`, `left`, `right`, `bottom`). No corners.
- Release **always** snaps to the nearest of the 4 targets. `.free` is transient during an in-progress drag only.
- Inset: `max(12, screen.auxiliaryTopLeftArea / safeArea)` plus Dock/Stage Manager visible frames. Do not hard-code 24pt.
- Default snap: **`.right`**. Legacy corner values decode as `.right`.

**Persistence:** `SnapState` keyed by **`NSScreen.deviceDescription["NSScreenNumber"]` as UInt32** (stable enough; on miss, fall back to frame-size hash). Persisted value is always `.snap(SnapPoint)`.

On unplug: if the stored display is gone, move the dock to the **main** screen’s same `SnapPoint`, or `.right` if missing.

**Dock orientation** (from the locked snap point):

| Position | Line axis | Growth | Order starts |
| --- | --- | --- | --- |
| Left midpoint | vertical | inward (right) | top |
| Right midpoint | vertical | inward (left) | top |
| Bottom midpoint | horizontal | inward (up) | left |
| Top midpoint | horizontal | inward (down) | left |

The pill is always **centered** on the midpoint. Dock overflow: **scroll along the line axis**, snap to items, **9 visible**. No `+N`. Never clip without a way to reach every marble.

**Focus popover** opens toward screen interior, ≤360pt wide, never over the Notch, attached to the marble. Autoscroll the focused marble into the visible window.

**Multi-display:** dock lives on the screen it was last dropped on (last-drop is the “which display” pref — no separate picker). Recalculate snap on `NSApplication.didChangeScreenParametersNotification`. Color space: **display-P3** drawables; error-hue red is authored in P3 so it matches across HDR/SDR.

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
  var isDemo: Bool
  var animationTime: Float          // last shader time; never reset to 0
}

enum SnapPoint: String, Codable, CaseIterable {
  case top, left, right, bottom     // default .right; legacy corners decode as .right
}

enum SnapState: Codable {
  case snap(SnapPoint)
  case free(x: Double, y: Double)   // display-local points
}
```

**Status reducer** (`AgentStore.apply(_ event: HookEvent)`), highest flag wins after the event is applied:

| Event | Mutation |
| --- | --- |
| `SessionStart` | Upsert by `session_id`. `source` from payload `source` / `matcher`: `resume`/`compact` **revives** the same id (keep seed, animationTime; clear currentTool; status `idle` until a prompt). `startup`/`fork`/`clear` = new turn history, same id if reused. |
| `UserPromptSubmit` | `turnOpen = true`, `status = thinking`, `sessionEndedAt = nil`, resume `animationTime` (do not zero). |
| `PreToolUse` | Show as `currentTool` phase `started`, `status = working`. If a chip is already live, enqueue (FIFO, cap 6). Extract summary per §11.4. Each live chip stays on screen **at least 500ms**. |
| `PostToolUse` | Mark the first in-flight tool `succeeded`. Keep it as the live chip until the 500ms dwell elapses, then show the next queued tool (also ≥500ms) or, if the queue is empty and `turnOpen`, `status = thinking`. Push onto `recentTools` when it leaves the live slot. `Stop` / `SessionEnd` clear immediately. |
| `PostToolUseFailure` | Same as post but phase `failed`. **Does not** set `error` (chip only). |
| `PermissionRequest` / needs-you `Notification` | `status = waitingOnUser`. |
| `Notification` `agent_completed` | Same as `Stop`. |
| `Stop` | `turnOpen = false`, `status = finished`, store preview from the transcript’s latest assistant **text** block (not thinking). Hook `last_assistant_message` is fallback only. **Start bloom** (skip if already `error`). |
| `StopFailure` | `turnOpen = false`, `status = error`, store preview as on `Stop`, **no bloom**, ease `errorHue` on. |
| `SubagentStart` | Append `SubagentRecord`. If a `Task` tool is in flight for the same spawn, keep the satellite and drop the extra Task chip. |
| `SubagentStop` | Remove that id from `subagents`. |
| `SessionEnd` | `sessionEndedAt = now`. Reason ∈ {process crash, `error`, non-zero, `prompt_input_exit` after `StopFailure`} → `error`; else keep `finished` or set `finished`. Linger **45s** then fade 300ms and remove. |
| Process death (pid gone, `turnOpen`) | `status = error`. |
| `parseError` POST | Ignore (no agent). |

**Error dismiss:** Focus shows a “Dismiss” text button that removes the marble immediately if `sessionEndedAt != nil`, or clears `error` → `idle` if the process is still alive. No other dismiss control.

**Idle discovery cap:** at most **5** `discovery` agents, and only if mtime < **2 hours** *and* a matching `claude` PID exists. JSONL-only ghosts without a PID are not shown (prevents a 24h flood). Discovery never overwrites a hooked agent.

**Overflow / cap:** hard cap **50** agents (oldest insertion evicted when inserting the 51st). Linger agents count. The dock shows insertion order, packs on leave, **9 visible** then scroll. No `+N` marble.

**Slot assignment:** array order is insertion order. Do **not** re-pack by status. `Identity.seed` = FNV-1a 64 of `session_id` UTF-8; persist as **hex string** in `seeds.json`. If `session_id` is missing, id = `"disc-" + hex(FNV(cwd + startedAt ISO8601))`.

---

## 9. Layout engine

`LayoutEngine.frames(agents:mode:snap:panelBounds:) -> [AgentID: MarbleFrame]`

```swift
struct MarbleFrame {
  var center: CGPoint               // panel coords
  var size: CGFloat                 // 36 always
  var z: Int
  var dim: CGFloat                  // always 0; highlight comes later
}
```

### 9.1 Default dock

Pill of 36pt marbles. Padding **10pt**. Item stack = marble 36 + 4pt gap + 3pt lights + 12pt to next marble (**55pt stride**). Max **9** visible, then scroll + snap to stride. Empty dock is **10×36pt**. Thickness when occupied = 56pt.

Use insertion order from `AgentStore.agents`. Do **not** re-pack by status.

### 9.2 Focus line

Same dock layout as Default (36pt, no dim). Card attaches to the hero marble, 12pt gap, toward screen interior. Autoscroll so the focused marble is among the 9 visible.

### 9.3 Hit testing

Each marble’s hit region is a **circle** of `size/2` **inside the dock stadium**. Dock chrome (glass padding) is a drag handle in Default and a dismiss target in Focus. Lattice-style gaps no longer exist; the pill is opaque. Hit tests the **interpolated visual** center/size this frame, not the animation target.

Drag vs click: movement ≥ **4pt** before mouse-up is a drag. Disabled while Focused.

---

## 10. Rendering architecture

### 10.1 Why Metal

Opaque gem-smoke discs at 36pt: one `MTKView`, instanced draws. Port of Paper Shaders `gem-smoke` (circle shape, interior only). No per-marble glass view. No glass-sphere raymarch.

**Not allowed for v1 pixels:** pre-rendered PNG sprite sheets as the identity, CSS/WebGL in a WKWebView.

### 10.2 Identity → uniforms

`Identity.params(seed: UInt64) -> MarbleParams` is pure and deterministic.

```swift
struct MarbleParams: Equatable {
  var colors: [SIMD4<Float>]      // 3...5 RGBA, unrestricted RGB, alpha 1
  var colorBack: SIMD4<Float>     // seeded; alpha 1
  var colorInner: SIMD4<Float>    // seeded, unused by the disc interior
  var innerDistortion: Float      // 0.1...0.8
  var size: Float                 // 0.7...1.0 (smoke feature scale)
  var angle: Float                // 0...360
}
```

Same `session_id` ⇒ same params across relaunch (`seeds.json` hex). Palette is identity, never status.

Shader constants (not seeded): circle fills the marble (`scale` unused), `innerGlow = 1`, `outerGlow = 0`, `offset = 0`.

### 10.3 Frame uniforms (status, not identity)

```swift
struct MarbleFrameUniforms {
  var time: Float                   // Agent.animationTime; never reset to 0
  var advection: Float              // leftover chrome; shader uses time only
  var pulse: Float
  var freeze: Float
  var hold: Float
  var errorHue: Float               // deferred chrome
  var bloom: Float                  // deferred chrome
  var attention: Float
  var dim: Float                    // always 0
  var rimBoost: Float
}

MotionEngine.timeScale(status):
  working, thinking     → 1.5
  waitingOnUser         → 0.25
  idle, finished, error → 0.05
  reduced motion        → 0
```

**Time:** Overlay advances `animationTime += dt * timeScale`. Reduced motion does not advance. A new `UserPromptSubmit` continues from the last value. **Never assign 0** on status change.

**Error hue / bloom / freeze-as-photograph:** deferred. The 3-light matrix marks thinking / tool / waiting / done / error.

**Reduced motion:** pref **or** `NSWorkspace.accessibilityDisplayShouldReduceMotion`: time scale **0** (freeze pose), layout **snaps**.

**Metal lifetime:** one `MTKView`, instanced draws, device/queue/pipelines owned by Render. Color space display-P3. Same shader at 36pt.

**Desktop bleed:** the Default dock **is** an `NSGlassEffectView` (`.regular`, adaptive). No extra border. Marbles sit on the glass. Never a painted black plate. No `MarbleGlassDisc` under each marble.

**Light/dark:** opaque discs read on a white Google Doc without a glass rim.

### 10.4 Three-light matrix

Drawn in AppKit *above* the Metal view. Same lights in Default and Focus. No icon chips on the Focus card.

```swift
enum LightColor { case off, white, green, red }

Indicators.lights(for:now:reducedMotion:) -> [LightColor]  // always 3
```

| State | Pattern |
| --- | --- |
| Idle | `[off, off, off]` |
| Thinking / working with no tool | White wave 0 → 1 → 2, ~640ms/step |
| `currentTool` set | Stable 1- or 2-light subset (seed + tool id) flashes white ~280/440ms. Failed tool stays white. |
| `waitingOnUser` | All white |
| `finished` | All green |
| `error` | All red |

Lights: 3×3pt, 1pt gap, 0.5pt corners. Off = gray @ 30%. On = `#FFF` / `#00E879` / `#E84200` + 4pt glow @ 100%. Row sits 4pt after the marble, across the dock axis. Reduced motion holds the current on-subset.

Satellites (if pref on): up to 3 dots, 8pt, 14pt outside the rim — unchanged, later.

---

## 11. Ingest contract

### 11.1 Transport

**v1 default:** HTTP `POST http://127.0.0.1:17832/hook`  
Fallback if bind fails: increment port and rewrite helper args via a small file:

`~/Library/Application Support/Marbles/ingest.json` → `{ "url": "http://127.0.0.1:17833/hook", "token": "<64 hex chars>" }`

Bind **127.0.0.1 only**. Do not fall back to `0.0.0.0`.

On first launch (or if `token` is missing / too short), generate 32 random bytes (`SecRandomCopyBytes`) and persist as hex. Reuse the existing token across relaunches so in-flight helpers do not race. File mode **0600**. Never log the token.

**Auth:** require header `X-Marbles-Token` equal to `ingest.json`’s `token` (constant-time compare). Missing or wrong token → **401**, do not apply the body. `X-Marbles-Hook: 1` is a label only, not a secret.

Unix socket is a fine v1.1 swap; keep the JSON body identical. The token still applies (header or equivalent).

**Response:** `204` empty on success. Helper treats connection-refused **and** 401 as success (exit 0). Timeout ≤150ms.

### 11.2 Helper

`marbles-hook` is **source-agnostic**:

1. Read stdin to EOF (Claude or Cursor JSON).
2. Read `ingest.json` for `url` and `token` (every invocation).
3. POST body = stdin bytes, headers `Content-Type: application/json`, `X-Marbles-Hook: 1`, `X-Marbles-Token: <token>`.
4. Exit 0 in all cases (including malformed stdin — still exit 0, optionally POST a `{ "parseError": true }`). Never print the token.

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
| `transcript_path` | `transcriptPath` | On `Stop`, read the jsonl **tail** for the latest assistant text block. Do not read on tool events. |
| `tool_name` | `toolName` | Preview / later chips |
| `tool_input` | `toolInputSummary` | Extract only: Read/Edit/Write → basename of `file_path`; Bash/Shell → first 40 chars of `command`; else omit. Max **80** chars. Never persist the object. |
| `last_assistant_message` | `lastAssistantMessage` | **Do not** show as Focus copy for Claude — it is often a one-line paraphrase. Preview comes from the jsonl tail. Cursor may still use `text` when no transcript exists. |
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

**Preview text:** memory only, max 8000 characters. Prefer the latest `type=assistant` text block from the jsonl tail on `Stop`; hook `last_assistant_message` is often a one-line paraphrase. Never persist `user_email`.

### 11.4.1 Cursor event map

Ingest detects Cursor payloads by `hook_event_name` camelCase (`sessionStart`, `preToolUse`, …) or presence of `conversation_id` + `cursor_version`.

| Cursor event | Treat as | Notes |
| --- | --- | --- |
| `sessionStart` | `SessionStart` | `session_id` == `conversation_id`. **Drop** if `composer_mode` is `ask` or `edit`. Keep `agent` and `is_background_agent == true`. |
| `sessionEnd` | `SessionEnd` | |
| `beforeSubmitPrompt` | `UserPromptSubmit` | |
| `preToolUse` / `postToolUse` / `postToolUseFailure` | same | Map tool names: `Shell`→Bash chip, `Write` covers Edit. Cursor `MCP: foo` → mcp chip. |
| `afterAgentThought` | thinking | `status = thinking` if `turnOpen` and no current tool. Do not store `text`. |
| `afterAgentResponse` | preview | `text` → `lastAssistantPreview` (cap 8000). Transcript tail wins when present. |
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

## 12. Jump-in

v1 jump-in is **open the matching app**. There is no Focus composer and no keystroke injection.

### 12.1 Focus copy and chrome

Button order, left to right: **Open Claude Code** (hidden if `source == cursor`) · **Open Cursor** (shown if `source == cursor`) · **Open Terminal** · **Open Conductor** (hidden unless cwd is a Conductor workspace). Demo / injected marbles show the buttons **disabled**.

Disabled (not hidden) when the app is missing or Terminal has no `cwd`, with tooltip: “Claude Code isn’t installed”, “Cursor isn’t installed”, “No working directory”, “Can’t find this terminal”, “Conductor isn’t installed”.

Preview: PRD precedence (waiting → tool → assistant → status word). Scrollable, 13pt, cap 8000 chars. Not a full transcript.

Return does not jump-in. Esc always dismisses Focus.

### 12.2 Adapters

`JumpIn` owns routing. Focus never shells out itself. `AppLaunching` is the `NSWorkspace` seam so tests can fake installs and running apps.

```swift
enum JumpKind { case claudeCode, cursor, terminal, conductor }

protocol AppLaunching {
  func applicationExists(bundleID: String) -> Bool
  func runningBundleIDs() -> Set<String>
  func open(_ url: URL) throws
  func openApplication(bundleID: String) throws
  func open(_ folder: URL, bundleID: String) throws
}
```

`JumpRouter.decision` returns visible / enabled / tooltip. `JumpRouter.open` launches. Demo and injected marbles stay visible and disabled (`tooltip`: “Demo.”).

| Target | Bundle ID (v1 lock; fix here if wrong) | Open |
| --- | --- | --- |
| Marbles | `dev.marbles.app` | — |
| Claude Code app | `com.anthropic.claude-code` | `claude://claude.ai/chat/<session_id>` (documented existing-chat deep link). If that fails, activate the app. Do **not** open `claude://code/new` (that starts a different session). |
| Cursor | `com.todesktop.230313mzl4w4u92`, then `com.cursor` | Open `cwd` with Cursor. Conversation-id targeting is stretch. |
| Terminal.app | `com.apple.Terminal` | Open `cwd` with a running emulator if detected, else Terminal.app |
| iTerm2 | `com.googlecode.iterm2` | |
| Ghostty | `com.mitchellh.ghostty` | |
| kitty | `net.kovidgoyal.kitty` | |
| Warp | `dev.warp.Warp-Stable` | |
| Conductor | `build.conductor.desktop` | Hide button if cwd is not a Conductor workspace; else activate Conductor |

Terminal resolution: prefer a running emulator from the table, else `open -a Terminal <cwd>`. Pid → TTY targeting is stretch.

**Bar for M3:** correct *app* ≥90%. Correct tab / Claude Code session is best-effort via the chat deep link.

Accessibility / Automation / Notifications prompt on first use of that feature, not before the first marble.

---

## 13. Persistence

Directory: `~/Library/Application Support/Marbles/`

| File | Contents |
| --- | --- |
| `prefs.json` | `{ "version": 1, "reducedMotion": false, "completionSound": false, "satellites": true, "launchAtLogin": false, "overlayHidden": false }` |
| `snap.json` | `{ "version": 1, "displays": { "<screenNumber>": { "snap": "right" } } }` |
| `seeds.json` | `{ "version": 1, "seeds": { "<session_id>": "<hex u64>" } }` |
| `ingest.json` | `{ "url": "http://127.0.0.1:17832/hook", "token": "<64 hex chars>" }` mode `0600` |

No transcript cache. Previews, cwd, pid, tool names live in memory only. `MARBLES_HOOK_DEBUG` logs are truncated to 2 KB/line, no stdin body, deleted after 24h.

Port constant: `Agents/IngestConstants.swift` `static let defaultPort = 17832`. Helper always re-reads `ingest.json` (url + token). On upgrade, app rewrites the hook command path and `ingest.json` **without rotating a valid existing token**.

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
| `LayoutTests` | 4 snap orientations; 36pt dock/focus; 10pt padding; 55pt stride; 9 visible then scroll; insertion-order pack; empty 10×36; cap 50. Run `./scripts/test.sh`. |
| `JumpInTests` | visibility by source; demo/injected disabled; missing app tooltips; Claude chat URL (never `code/new`); Cursor opens cwd; Terminal prefers a running emulator |
| `StatusTests` | reducer table in §8; error vs finished vs waiting vs PostToolUseFailure |
| `IdentityTests` | same seed ⇒ same params; 3–5 colors; distortion/size ranges |
| `HookContractTests` | helper exits 0 on refused connection and bad JSON; fixtures decode; ingest token match / reject |
| `HooksMergeTests` | idempotent merge / undo; JSONC comments survive |
| `MotionTests` | time scales 1.5 / 0.25 / 0.05; reduced motion is 0; never reset time |
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
| Inject 9 / 10 / 50 agents | Nine visible, then scroll; hard cap |
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
| **W1** | Mode + Layout + snap | Dummy 3 agents; Default/Focus; 4 snap points | W0 | Placeholders in a glass pill. Click marble → Focus card. Drag to all 4 midpoints. Outside the pill click through. |
| **W2** | AgentStore + Ingest + helper | Fake + live events update status | W0 | Debug inject changes status. `curl` a fixture at `:17832/hook` **with `X-Marbles-Token` from ingest.json** updates a marble; the same POST without the token is `401` and does not change the pile. Optional: install hooks and run a real Claude **or** Cursor Agent turn and watch a marble appear. |
| **W3** | Lights + motion | Works against dummy *or* live store | W1, W2 | Thinking waves. Tool calls flash 1–2 whites. Waiting all white. Finished all green. Error all red. |
| **W4** | Metal + Identity | Gem-smoke discs at 36pt | W1 | Distinct palettes, opaque discs, no per-marble glass. Same marble on a white Google Doc **and** a dark desktop. Debug cycle seeds. |
| **W5** | Focus popover + preview | Actions land in W6 | W1, W2 | Preview copy order (waiting / tool / text). Hover a marble to enter Focus; hover off the pill+card returns to Default. Card stays on-screen at every snap. |
| **W6** | Jump-in adapters | Claude Code / Cursor / Terminal / Conductor | W5 | Each visible **enabled** button opens the right **app** (Claude chat deep link when we have a session id). Cursor-sourced marbles show Open Cursor, not Claude Code. No reply field. |
| **W7** | Hook installer + demo + prefs | Repair / undo both configs | W2 | First-run checklist. Demo marble if empty. Confirm `~/.claude/settings.json` **and** `~/.cursor/hooks.json` contain `marbles-hook`. Undo removes only ours. Reduced motion snaps. |
| **W8** | Packaging | cask / install.sh / notarize | W7 | Clean machine / other account: install in <5 min, see a marble. |

Suggested pairing: **W0→W1** and **W0→W2** in parallel after the panel exists; **W4** can prototype in a standalone MTKView **as long as that target is launchable for visual review**.

---

## 17. Milestone mapping

| Milestone | Streams | Done when |
| --- | --- | --- |
| **M0 Skeleton** | W0, W1 | Drag, snap, three dummy marbles, Default + Focus |
| **M1 Live agents** | W2, W3, W7 **hook merge only** | Real Claude **or** Cursor sessions; working/freeze/error hue; chips; bloom |
| **M2 Material** | W4 | Gem-smoke opaque discs; seeded 3–5 color palettes |
| **M3 Jump-in** | W5, W6 | Preview + open actions (Claude Code / Cursor / Terminal / Conductor) |
| **M4 Install** | W7 finish (demo, checklist, prefs), W8 | <5 min engineer path |

---

## 18. Decisions already made

| Decision | Choice | Why |
| --- | --- | --- |
| Stack | Native Swift / AppKit / SwiftUI / Metal | Overlay + glass; PRD rejects Electron |
| Dock hover | Marble → Focus | Hover switches; click does not dismiss |
| Midpoint dock | Vertical on left/right, horizontal on top/bottom; centered | PRD §7.2 |
| Empty overlay | 10×36 glass pill | Still centered on the snap |
| Error art | Red hue filter, no bloom | Keep identity; no fractures |
| Subagents | Chips / satellites only | One marble per parent session |
| Order | Insertion order; pack on leave | No sticky holes in a 1D pill |
| Overflow | Scroll after 9 visible; hard cap 50 | No `+N` marble |
| Snap | 4 midpoints; default and migrate to **right** | No corners |
| Freeze time | Never reset `animationTime`; reduced motion stops the clock | Resume from pose |
| Time scale | 1.5 working/thinking, 0.25 waiting, 0.05 else | Status is speed |
| Window | `.accessory` + `statusBar` + join-all | No Dock; no `.stationary` |
| Ingest | Local HTTP :17832 + helper + `X-Marbles-Token` | Unauthenticated localhost POSTs must not mutate agents |
| Reply | **Out of v1** — no Focus composer, no keystroke injection | Jump-in only |
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
| Accessibility | Not required for v1 jump-in (`NSWorkspace` only) | Do not prompt. |
| Files | None extra if we stay in the home folder via POSIX | Do not ask for Full Disk Access. If `~/.claude` is unreadable, first-run shows “Can’t read Claude sessions.” |
| Local network | If macOS prompts for 127.0.0.1 | `NSLocalNetworkUsageDescription`: “Marbles receives local status from Claude Code hooks on this Mac.” |
| Sandbox | **Off** | Sandbox would break hooks and jump-in. |

Do not request TCC before a marble is on screen.

---

## 20. Open implementation risks

1. **Window level vs. full-screen / Stage Manager** — needs device testing; may require a fallback “always on this Space only.”
2. **Claude Code session-level activation** — `claude://claude.ai/chat/<id>` is documented for chats; Code-only sessions may fall back to activating the app.
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
| Default dock | Pill-shaped `NSGlassEffectView` of 36pt marbles |
| time scale | Status multiplies `dt` into `animationTime` |
| Marbles-owned hook | settings.json entry whose command path contains `marbles-hook` |
