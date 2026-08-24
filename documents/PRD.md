# Marbles — Product Requirements Document

**Status:** Draft  
**Date:** 2026-08-23  
**Product:** Marbles  
**Platform:** macOS  
**Primary users:** Software engineers running one or more local Claude Code agents  
**Implementation contract:** [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 1. Summary

Marbles is a native Mac overlay that represents every local Claude Code agent as a floating, photorealistic marble on the desktop. The marbles stay above other apps — like Dock icons or Android chat heads — so you can glance at agent activity while reading a Google Doc, sitting in Slack, or otherwise looking away from the terminal and the Claude Code app.

Each marble is procedurally generated and visually distinct. While an agent is working, its marble subtly animates. When the agent finishes, the marble freezes and signals completion in a way that is obvious from across the room. Small iconographic chips communicate thinking and tool calls without requiring you to read text.

The product has three interaction modes:

1. **Cluster** (default) — agents pack into a compact isometric 3×3×3 lattice.
2. **Active** — the cluster expands into a line so you can pick one agent.
3. **Focus** — a single agent opens a preview and shortcuts into Claude Code, Terminal, or Conductor, with an optional reply field.

Installation must be completable by any software engineer in under five minutes.

Visual north star: [references/marble-visual-reference.png](references/marble-visual-reference.png).

---

## 2. Problem

Engineers now routinely run several Claude Code agents in parallel — in Terminal, the Claude Code Mac app, and Conductor workspaces. Those agents keep working after you tab away. The existing surfaces all require you to look at them:

- The terminal is buried behind other windows.
- The Claude Code app is a full window, not a glanceable HUD.
- Conductor is excellent for review, but it is still an app you have to open.
- Existing hook dashboards are browser tabs, not desktop chrome.

There is no always-visible, low-attention way to answer:

- Which of my agents are still working?
- Which one just finished?
- What is this one doing right now (thinking vs. reading vs. editing vs. waiting)?
- How do I jump back into *this* agent without hunting through windows?

Marbles is that glanceable HUD.

---

## 3. Goals

1. Keep every live local agent visible above other apps at all times.
2. Make identity instant: you should recognize “the orange silk one” without reading a label.
3. Make status glanceable at 72×72: working, thinking, tool-in-flight, waiting, finished, error.
4. Get from “I see the marble” to “I’m in that agent’s surface” in one or two clicks.
5. Stay out of the way. Cluster mode is a small corner ornament, not a dashboard.
6. Install in under five minutes, including wiring Claude Code hooks.

### 3.1 Non-goals (v1)

- Replacing Conductor, Claude Code, or Terminal as the place you actually do the work.
- A full conversation transcript viewer or kanban board.
- Remote / cloud-only agent fleets as the primary target (local Mac sessions first).
- Windows or Linux.
- Spawning, killing, or orchestrating agents (watch and jump-in only).
- Multiplayer or sharing marbles across machines.

---

## 4. Users and jobs to be done

**Primary user:** a software engineer on a Mac running 1–12 local Claude Code sessions while doing other work.

**Jobs:**

| Job | Success looks like |
| --- | --- |
| Peripheral monitoring | From Slack or a doc, I can tell which agents are busy vs. done without switching apps. |
| Identify an agent | I pick the right marble by appearance, not by reading a project path. |
| Inspect one agent | I expand the cluster, click one marble, and see what it is doing. |
| Jump back in | From Focus I open the correct Claude Code window, terminal, or Conductor workspace. |
| Reply without fully context-switching | If possible, I send a short reply to the agent’s latest question from Focus. |

---

## 5. Product principles

1. **Glance first.** If a status needs a paragraph, it failed. Prefer motion, color, and icons.
2. **Physical objects, not avatars.** Marbles are glass spheres with interiors, not emoji or user initials.
3. **Stay above, stay small.** Never steal the screen. Cluster mode is a corner. Focus is a compact card, not a panel that covers Slack.
4. **One marble, one agent.** v1: one circle per parent session. Subagents are chips or satellites, never a second marble.
5. **Local and quiet.** No telemetry. Hooks must never block Claude Code. If Marbles is quit, agents keep working.
6. **Install is a feature.** A clever HUD that takes 30 minutes to wire is a failed product.

---

## 6. Modes

### 6.1 Cluster (default)

Agents appear as a packed **isometric 3×3×3 lattice** — a small cube of spheres on the desktop. This is the idle, always-on posture.

- Each marble is **at most 72×72 CSS/pt pixels** in this mode (Retina: 144×144 backing pixels is fine; the hit target and layout size stay ≤72pt).
- The whole cluster should read as one object, similar to a pile of marbles in a tray, not a spreadsheet of icons.
- Occupied slots only. Empty lattice positions are not drawn.
- **Sticky slots:** `session_id` maps to a lattice index for the life of that marble (including the 30–60s SessionEnd linger). Removing an agent must not shift the others. Vacated indices are reused by the next new agent.
- Capacity: **27 lattice slots**. If more than 27 agents are live (linger counts), show **26 identity marbles + one `+N` overflow marble** in a lattice slot. Evict the non-focused agent with the oldest `lastEventAt` (not spatial “furthest”). The overflow marble is not a seeded identity. Clicking it enters Active with the full scrollable list.
- Clicking a **marble, chip, or the overflow marble** enters Active mode. Gaps between spheres click through to the desktop. “The cluster” means the union of those circles, not the bounding box.
- The cluster is the snap-friendly form: it docks to corners and edge midpoints (see §7).

**Why isometric, not a flat 3×3:** a flat grid looks like a dock. An isometric pile matches the physical-marble metaphor and keeps the footprint small while still showing depth when many agents are running.

### 6.2 Active

The lattice unfolds into a **single line** so you can target one agent.

- Click a marble to enter Focus for that agent.
- Click empty desktop / press `Esc` to collapse back to Cluster.
- Layout **adapts to snap position** (see §7.2).
- Marbles may grow slightly (up to ~88pt) so they are easier to hit, but they should still feel like the same objects.
- Hovering a marble previews the current tool icon + a one-line status without entering Focus. No permanent project-name captions under Cluster/Active marbles.

### 6.3 Focus

Selecting one marble opens a compact HUD anchored to that marble.

**Must show**

- The focused marble, still animated/frozen according to live state.
- A short preview of current work, **first matching**: (1) “Waiting for you” if `waitingOnUser`, (2) current tool line (“Editing `AuthService.swift`”) if a tool is in flight, (3) truncated latest assistant text, else (4) “Working…” / “Done” / “Something went wrong” from status.
- Recent activity as icon chips (same vocabulary as §9).
- Actions:
  - **Open Claude Code** — bring the matching Claude Code desktop session / window forward.
  - **Open Terminal** — bring the matching terminal / iTerm / Ghostty / kitty tab or pane forward when we can resolve it; otherwise open a new terminal in the session cwd.
  - **Open Conductor** — open the matching [Conductor](https://conductor.build) workspace when the session belongs to one.
- A reply composer if we can deliver a message into the live session (see §10.4). Disabled with an honest reason when we cannot.

**Must not**

- Become a second Claude Code. No full transcript, no file tree, no diff reviewer.
- Cover the whole screen. Target size: roughly a large tooltip / small popover (≤360pt wide).

**Exit:** click the focused marble again, click outside the popover (pass-through), or press `Esc` → Active. From Active, `Esc` or click outside → Cluster. Clicking a *different* marble while in Focus **switches** Focus to that agent (does not collapse).

### 6.4 Mode transitions

| From | To | Trigger | Motion |
| --- | --- | --- | --- |
| Cluster | Active | Click cluster | Lattice unpacks into a line; 240–320ms spring |
| Active | Cluster | Esc / click outside | Line packs back into lattice |
| Active | Focus | Click one marble | Other marbles dim/recede; popover grows from the marble |
| Focus | Active | Esc / click outside popover | Popover collapses |
| Any | Cluster | Drag to a new snap point | Optional: collapse first so snapping stays predictable |

Transitions must be interruptible. Users who click Cluster → marble quickly should land in Focus without waiting for Active to finish.

---

## 7. Placement, dragging, and snapping

The overlay is an always-on-top floating panel that joins every Space and sits above full-screen apps where the OS allows (`NSPanel` at a high window level, `canJoinAllSpaces` + `fullScreenAuxiliary`).

### 7.1 Cluster snap targets

Cluster mode snaps to **eight points** on the current display:

- Four corners: top-left, top-right, bottom-left, bottom-right
- Four edge midpoints: top, bottom, left, right

Behavior:

- Drag anywhere on the cluster (not just a chrome handle).
- Release near a snap target → magnetic snap (threshold ~48pt).
- Release elsewhere → stay where dropped (free position), but Active-mode orientation still uses the *nearest* edge/corner (see below).
- Persist snap (or free position) per display. Multi-monitor: the cluster lives on the display it was last dropped on.
- Avoid the menu bar, Notch, Dock, and Stage Manager strip. Snap points inset by safe-area padding (~12pt).

### 7.2 Active-mode orientation

When entering Active, the line **orients from the current snap / nearest edge**:

| Position | Active layout |
| --- | --- |
| Left edge midpoint | Vertical line, growing inward (to the right) |
| Right edge midpoint | Vertical line, growing inward (to the left) |
| Bottom edge midpoint | Horizontal line, growing inward (up) |
| Top edge midpoint | Horizontal line, growing inward (down) |
| Any corner | **Vertical line**, growing inward along the nearest vertical edge |

Corner → vertical is an explicit product decision: corners should feel like a side stack (Dock-on-the-side), not a taskbar.

If the line would overflow the display, it scrolls with a fade, or wraps once as a second rank. It must never go off-screen without a way to reach every marble.

### 7.3 Focus anchoring

The Focus popover opens toward the interior of the screen — never off the display, never over the Notch. If the marble is on the left edge, the card opens to the right, and so on.

### 7.4 Window behavior

- Clicks on marbles and the Focus card are interactive.
- Clicks on fully transparent pixels pass through to apps beneath, so a 3×3×3 cluster does not create a large invisible hit rectangle.
- The app has no Dock-occupying document windows in normal use. A menu-bar extra (tiny marble or status item) is acceptable for Quit / Preferences / Install hooks.
- Hide-on-Cmd-H should *not* hide Marbles, even when Marbles is key for the Focus reply field. Provide an explicit “Hide Marbles” in the menu bar instead.

---

## 8. Visual design — frosted marbles

### 8.1 North star

Treat [references/marble-visual-reference.png](references/marble-visual-reference.png) as binding for material quality, not as a sprite sheet to copy.

The reference shows glass spheres on black: sharp speculars, colored inner glow, and interiors that look like captured fluids, crystals, or tiny worlds. Marbles are physical objects, not flat badges.

### 8.2 Material recipe

Every marble is a **glass shell + interior volume + lighting**:

| Layer | Look |
| --- | --- |
| Shell | Clear / lightly frosted dielectric. Fresnel rim. One hard specular (typically upper-left) plus a softer secondary bounce. |
| Frost | Micro-roughness and a thin cloudy film so they read as “frosted marble,” not a soap bubble or a chrome ball. Frost amount varies by identity. |
| Interior | A unique procedural field: silk ribbons, oil-slick iridescence, cellular/crystalline cracks, nebula clouds, prismatic shafts, or a miniature landscape. Interiors are the identity. |
| Glow | Subtle colored bleed into the desktop so the marble lifts off whatever is behind it. |
| Contact | Optional soft ground shadow / occlusion so a pile of marbles feels stacked, not composited stamps. |

Photorealistic *enough*: convincing at 72pt on a Retina display. Not offline path-traced. A real-time Metal (or SceneKit / custom shader) path is expected.

### 8.3 Identity — procedural generation

Marbles are **seeded**, not hand-drawn.

- Seed from a stable agent id (`session_id`, falling back to a hash of cwd + started_at).
- The same agent always gets the same marble for the life of that session, and ideally across resume.
- Diversity must be high enough that 9 agents on screen are not “nine slightly different blue orbs.” Vary **hue, interior family, frost, inclusion density, and luminosity** independently.

**Interior families** (from the reference, used as a generator palette):

1. **Silk / fluid** — swirling ribbons, cream-into-fire, oil-on-water.
2. **Crystalline / cellular** — cracked ice, scales, lattice, gold-to-teal.
3. **Prismatic** — internal rainbow shafts, caustic streaks.
4. **Nebula** — soft gas clouds, pearlescent gradients.
5. **Landscape / cameo** — a compressed scenic interior (moons, ridges). Use sparingly; it is the most memorable family.
6. **Core / inclusion** — mostly clear glass with a geometric or mineral heart.

Do not map family → status. Family is identity. Status is communicated by motion and chips (see §9), so a “fire silk” marble can be idle, working, or done without changing species.

### 8.4 Legibility on real desktops

The reference is on black. Real desktops are light docs, busy Figma files, and wallpaper.

- Marbles must remain readable on light *and* dark backgrounds (rim light + faint backdrop blur behind the cluster is allowed).
- Do not draw a permanent black plate behind the cluster. The desktop should show through.
- Minimum contrast: a white or light marble still needs a visible rim on a white Google Doc.

### 8.5 Scale

| Mode | Marble size | Notes |
| --- | --- | --- |
| Cluster | ≤72×72 pt | Hard cap |
| Active | 72–88 pt | Same asset, slightly larger hit target |
| Focus | 96–120 pt | Hero marble in the popover |

Shaders must look good at all three sizes. Avoid features that vanish at 72pt (hairline cracks, 2pt text inside the sphere).

---

## 9. Motion, completion, and indicators

These rules apply in **every mode**. Cluster is not allowed to become a static pile that only “comes alive” after you click.

### 9.1 Agent activity → marble motion

| Agent state | Marble |
| --- | --- |
| Working (tools in flight) | Interior slowly advects: silk drifts, nebula boils, crystals catch light. Specular may creep. Amplitude stays subtle — living object, not a loading spinner. |
| Thinking (model inference, no current tool) | Slower, deeper pulse of inner luminosity. Surface mostly still. Optional faint “breathing” frost. |
| Waiting on user / permission | Motion pauses mid-swirl. A persistent attention chip (see below). |
| Finished / turn complete | **Freeze.** Interior locks. Specular holds. The object becomes a still photograph of itself. |
| Error / crashed session | Freeze, then apply a full-marble **red hue filter** over the existing identity (the silk/crystal/landscape is still recognizable, just shifted into red). No cracks, fractures, or error badges on the art. The filter eases on (~250ms) and stays until the session recovers or is dismissed. |

When a new turn starts, motion resumes from the frozen pose — do not randomize the interior on every turn.

### 9.2 Finished — noticeable in every mode

“Freeze” alone is too quiet if you are reading Slack. Completion needs a **one-shot signal** that works at Cluster scale:

1. Motion eases to a stop.
2. A brief completion bloom: rim-light flash, a single expanding glass ring, or a caustic sweep (~400–700ms).
3. A settled “done” rest state: slightly brighter rim or a small resolved check chip that remains until the next turn or until dismissed.
4. Optional OS notification and/or a very short tactile sound, off by default or following macOS notification settings.

The completion signal must be visible when the cluster is 72pt in a corner. If you cannot see “done” without entering Active, it failed.

If several agents finish in a short window, stagger the blooms so the cluster does not strobe.

### 9.3 Thinking and tool-call indicators

Status is **icon-first**. Prefer a small chip on the marble’s rim or in a tight orbit over text.

**Thinking**

- Distinct from tool chips (e.g. a dim comet, ellipsis constellation, or inner-core pulse glyph).
- Visible in Cluster. No label required.

**Tool calls**

Show the *current* tool as a live chip. Optionally keep the last 2–3 as a short trail that fades.

| Tool / event | Icon direction |
| --- | --- |
| Thinking / inference | Pulse / comet |
| Read | Book / file |
| Write / Edit / NotebookEdit | Pencil |
| Bash | Terminal chevron |
| Grep / Glob | Magnifier |
| WebSearch / WebFetch | Globe |
| Task / subagent spawn | Branching node |
| Git (`Bash` that is clearly git, or future Git tool) | Branch |
| Permission / needs input | Question / tap |
| Stop / turn complete | Check |
| Tool failure | Small fault mark |

MCP tools fall back to a generic plug/spark icon plus a one-letter or truncated server hint when space allows.

In Cluster, show **one** live chip (current tool or thinking). In Active, show the live chip plus a short trail. In Focus, show a compact recent-activity row.

Chips must stay legible at 72pt: ~12–16pt marks sitting on the rim, not icons dropped into the interior where the silk texture will hide them.

### 9.4 Needs-you state

If Claude Code fires `Notification` types such as `permission_prompt`, `idle_prompt`, or `agent_needs_input`, the marble should out-rank ordinary working motion: freeze-or-hold, plus a repeating-but-polite attention pulse until the user opens Focus or the prompt clears. This is different from “finished.”

---

## 10. Agent model and integrations

### 10.1 What counts as an agent

v1 surfaces **local coding-agent sessions** on this Mac:

- Claude Code: CLI, desktop app, and Conductor-launched sessions
- Cursor: Agent Chat and background agents (not Tab, Ask, or inline Cmd+K edits)

**v1:** parent session = marble. Subagents are chips and optional satellite dots on the parent only — never a second marble, regardless of duration. Do not double-count a `Task` tool chip and a `SubagentStart` as two extras; prefer the subagent satellite when both fire.

### 10.2 Live event source

Primary source: the same `marbles-hook` helper, installed in **two** places:

- Claude Code: merge into `~/.claude/settings.json` (Marbles owns only entries whose command path contains `marbles-hook`)
- Cursor: merge into `~/.cursor/hooks.json` (user-level, so every project’s agents appear). Native Cursor format, not a second helper binary.

Cursor has a parallel hook API ([docs](https://cursor.com/docs/hooks)): command hooks, JSON on stdin, `sessionStart` / `preToolUse` / `postToolUse` / `stop` / `subagentStart` / etc. It can also load Claude’s `settings.json` if “Third-party skills” is on — **do not rely on that**. Always write the native `~/.cursor/hooks.json` so Marbles works without that toggle.

Gaps vs Claude: Cursor has **no** `Notification` or `PermissionRequest`, so needs-you is weaker. It **does** have `afterAgentThought` (better thinking signal) and `stop.status` of `completed` | `aborted` | `error`. Tool names differ (`Bash` → `Shell`, `Edit` → `Write`). Identity key is `conversation_id` (same as `session_id` on `sessionStart`).

Do not persist Cursor’s `user_email` field.

Subscribe at least to:

| Hook | Use |
| --- | --- |
| `SessionStart` | Create / resume a marble |
| `SessionEnd` | Linger **30–60s** in `finished` or `error`, then fade and remove. Linger **counts** toward the 27-slot cap. |
| `UserPromptSubmit` | Mark a new turn; resume motion |
| `PreToolUse` / `PostToolUse` / `PostToolUseFailure` | Tool chips |
| `Notification` | Needs-you + `agent_completed` |
| `Stop` / `StopFailure` | Finished / fault; `last_assistant_message` for Focus preview |
| `SubagentStart` / `SubagentStop` | Satellites / chips |
| `PermissionRequest` | Needs-you |

Hooks must be `async: true` (or equivalent) and **always exit 0**. If Marbles is not running, the hook is a no-op. Never block a tool call.

Transport: local HTTP or a Unix socket to the Marbles app (e.g. `127.0.0.1` on a fixed high port, or `~/Library/Application Support/Marbles/marbles.sock`).

Secondary sources, used to discover sessions that started before hooks were installed:

- `~/.claude/projects/**/*.jsonl` transcripts
- Process scan for `claude` PIDs (shown as idle until a hook fires)

### 10.3 Jump-in targets

| Action | Behavior |
| --- | --- |
| Open Claude Code | Activate the Claude Code Mac app and, if the OS/app allows, the matching session. Hidden for Cursor-sourced marbles. |
| Open Cursor | Activate Cursor and the workspace for Cursor-sourced marbles. Hidden otherwise. |
| Open Terminal | Resolve cwd + PID → frontmost terminal emulator tab/pane (Terminal.app, iTerm2, Ghostty, kitty, Warp — support what we can detect; document the rest). Fallback: `open -a Terminal <cwd>`. |
| Open Conductor | If the session cwd is a Conductor workspace (typically under `~/conductor/workspaces/...`) or we can resolve a workspace id, open that workspace in [Conductor](https://conductor.build). Hide the button when no mapping exists. |

v1 can ship with best-effort window targeting. Perfect tab-level focusing is a stretch; opening the right app + cwd is the bar.

### 10.4 Reply from Focus (stretch-but-desired)

Goal: type a short message and send it to the live agent.

Preferred order:

1. Official Claude Code remote-control / stdin / resume API if one exists for the running session.
2. Conductor session message API when the agent is a Conductor-managed session and a local or authenticated path exists.

**v1 does not send keystrokes** (no tmux / iTerm `send-keys`). If neither path is reliable, hide the composer and show “Open in Claude Code to reply.” Do not pretend a reply was delivered.

---

## 11. Installation

**Bar:** a software engineer who already has Claude Code goes from zero to marbles on the desktop in **under five minutes**, without reading a novel.

### 11.1 Happy path

One of:

```text
brew install --cask marbles
```

or a single documented script:

```text
curl -fsSL https://<release-host>/install.sh | bash
```

The installer must:

1. Place `Marbles.app` in `/Applications`.
2. Launch it.
3. Install / merge Claude Code hooks (with a visible confirmation and a one-click undo).
4. Prompt for Accessibility / Automation permissions only if jump-in or reply needs them — after first launch, not as a wall of dialogs before any marble appears.
5. Show a **demo marble** only on first launch, and only if discovery finds no live PID and no transcript activity in the last **2 hours**. Remove it the moment a real session appears. Later empty launches show an empty snap point (menu bar still proves the app is running), not another demo.

### 11.2 Constraints

- No “clone this repo, brew install cmake, open Xcode, provision a team.”
- Building from source is allowed as a *secondary* path for contributors, not the engineer-install path.
- Hook install is idempotent and does not clobber unrelated user hooks.
- Uninstall removes the app, the hooks Marbles added, and (optionally) Application Support data.

### 11.3 First-run checklist (in-app)

- Hooks: installed / missing / error (Claude `settings.json` **and** Cursor `hooks.json`)
- Claude Code detected
- Cursor detected
- Conductor detected (optional)
- Accessibility (only if needed)
- “Start a Claude Code session to see a live marble”

---

## 12. Information architecture (minimal)

**Menu bar extra**

- Show / Hide overlay
- Preferences (snap, reduced motion, notifications, hook repair)
- Install / Repair hooks
- About / Quit

**Preferences (v1, small)**

- Reduced motion (still freeze + completion ring + error hue; no interior advection; no attention pulse; layout snaps instead of springs)
- Follow system Reduce Motion as well as the pref
- Completion sound on/off
- Show subagent satellites
- Launch at login
- Snap display is **last-drop**, not a separate picker (remove “which snap display”)

No account. No cloud. No project.

---

## 13. Technical direction (guidance, not a lock)

Recommended stack for v1:

- **App:** native Swift, SwiftUI + AppKit overlay (`NSPanel`), menu bar extra.
- **Marbles:** Metal shader (or SceneKit with custom materials). One draw per marble, shared atlas of noise / HDRI. Seed → parameter block → GPU.
- **Ingest:** tiny local listener inside the app + a hook helper binary that POSTs JSON and exits immediately.
- **State:** in-memory + a small on-disk cache of seed ↔ session_id so identity survives relaunch.

This is an overlay with a handful of animated spheres, not a web dashboard wrapped in a WebView. Electron is the wrong default: window-level, click-through, and glass rendering will fight you.

---

## 14. Privacy and trust

- All event data stays on the machine.
- Hooks send session metadata, tool names, and truncated preview text to localhost only.
- Do not upload transcripts, prompts, or tool inputs anywhere.
- Permission to read `~/.claude` and to control other apps is requested with a plain-language explanation.
- Open-source or inspectable hook helper so engineers can see what leaves Claude Code.

---

## 15. Success metrics

Qualitative (v1 is a personal / small-audience tool):

- Time-to-first-marble after install < 5 minutes for someone who already has Claude Code.
- A user running ≥3 agents can identify a specific agent from Cluster without opening Active, in informal testing.
- Finished-state recognition from a typical viewing distance (laptop at arm’s length, cluster in a corner) without entering Active.
- Jump-in from Focus reaches the correct *app* ≥90% of the time; correct *session/tab* is a stretch metric.

---

## 16. Milestones

### M0 — Skeleton

- Git repo, overlay window, drag + 8-point snap.
- Three placeholder spheres, mode transitions (Cluster / Active / Focus) with dummy data.

### M1 — Live agents

- Hook installer + ingest (prefs/demo UI can be a stub; polish is M4).
- One marble per live session; working vs. frozen vs. error (red hue filter).
- Tool chips + thinking glyph.
- Completion bloom.

### M2 — Material

- Procedural frosted-marble renderer at reference quality (72pt).
- Stable seeds, ≥6 interior families, light/dark desktop legibility.

### M3 — Jump-in

- Open Claude Code / Terminal / Conductor from Focus.
- Preview of latest assistant message.
- Reply if a safe delivery path exists; otherwise honest fallback.

### M4 — Install

- Signed app, Homebrew cask (or equivalent one-liner), first-run demo marble, hook repair, uninstall.

---

## 17. Open questions

**Decided for v1** (see ARCHITECTURE.md): sticky lattice slots; overflow is 26 + `+N`; cluster click is occupied circles only; subagents are never a second marble; no keystroke reply; demo is first-launch-only after a 2h discovery check; packed isometric lattice, not a rigid empty cube.

Still open:

1. **Claude Code window targeting.** Depends on what the desktop app exposes (Apple Events, URL scheme, session id). May remain best-effort.
2. **Reply delivery path.** Official IPC vs Conductor only; both may be unavailable at ship.
3. **Codex / other Conductor runtimes.** Cursor Agent is in v1 via native hooks. Codex-in-Conductor is later.
4. **Notch, Stage Manager, and multiple full-screen Spaces.** Overlay policy will need device testing.
5. **Click-marble-skips-Active** as a later experiment. v1 always goes Cluster → Active first.

---

## 18. Appendix A — Mode map

```text
                    click cluster
   ┌──────────┐  ───────────────►  ┌──────────┐  click marble  ┌──────────┐
   │ Cluster  │                    │  Active  │ ─────────────► │  Focus   │
   │ 3×3×3    │  ◄───────────────  │   line   │ ◄───────────── │ preview  │
   │ isometric│   Esc / outside    └──────────┘   Esc/outside  │ + open   │
   └──────────┘                                                └──────────┘
        ▲
        │  drag → snap to 4 corners + 4 edge midpoints
```

Active line axis: horizontal on top/bottom edges, vertical on left/right edges **and all corners**.

---

## 19. Appendix B — Visual reference notes

Source file: `documents/references/marble-visual-reference.png`.

What to steal from the frame:

- Glass shells with a hard upper specular and a colored inner light.
- Interiors that feel like matter (silk, crystal, prism, landscape), not flat fills.
- High saturation and iridescence so identities separate at a glance.
- Variation in *kind*, not just hue — a cracked teal marble must never be confused with a fire-silk marble even if both are “warm.”

What not to steal:

- A black rectangular backdrop. Marbles float on the real desktop.
- Using interior family as a status color language. Error is a **red hue filter** over the existing marble, not a different species.
- So much micro-detail that 72pt reads as noise.

---

## 20. Appendix C — Glossary

| Term | Meaning |
| --- | --- |
| Cluster | Default isometric 3×3×3 pile. |
| Active | Expanded line for selection. |
| Focus | Single-agent preview + jump-in. |
| Marble | One procedurally generated glass sphere bound to one agent. |
| Chip | Tiny rim/orbit icon for thinking or a tool. |
| Error hue | Full-marble red hue shift applied on crash/error; identity remains. |
| Conductor | The Mac app at conductor.build for parallel local agents in git worktrees. |
| Hook | Claude Code lifecycle callback used to stream status into Marbles. |
