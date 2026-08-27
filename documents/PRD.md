# Marbles — Product Requirements Document

**Status:** Draft  
**Date:** 2026-08-23  
**Product:** Marbles  
**Platform:** macOS  
**Primary users:** Software engineers running one or more local Claude Code agents  
**Implementation contract:** [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 1. Summary

Marbles is a native Mac overlay that represents every local Claude Code agent as a floating, opaque gem-smoke marble on the desktop. The marbles stay above other apps — like Dock icons or Android chat heads — so you can glance at agent activity while reading a Google Doc, sitting in Slack, or otherwise looking away from the terminal and the Claude Code app.

Each marble is procedurally generated and visually distinct. Status shows up as animation speed and a 3-light matrix after each marble. Completion bloom and error hue on the orb itself are later chrome.

The product has two interaction modes:

1. **Default** — agents sit in a line inside a pill-shaped glass dock at an edge midpoint.
2. **Focus** — a single agent opens a preview and shortcuts into Claude Code, Terminal, or Conductor.

Installation must be completable by any software engineer in under five minutes.

Visual north star: [references/marble-visual-reference.png](references/marble-visual-reference.png). Default dock posture: the screenshot in this overhaul (36pt marbles in a glass pill).

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
2. Make identity instant: you should recognize “the teal swirl one” without reading a label.
3. Make status glanceable at 36×36: working, thinking, tool-in-flight, waiting, finished, error.
4. Get from “I see the marble” to “I’m in that agent’s surface” in one or two clicks.
5. Stay out of the way. Default mode is a slim midpoint dock, not a dashboard.
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
| Inspect one agent | I click a marble in the dock and see what it is doing. |
| Jump back in | From Focus I open the correct Claude Code window, terminal, or Conductor workspace. |
| Reply without fully context-switching | If possible, I send a short reply to the agent’s latest question from Focus. |

---

## 5. Product principles

1. **Glance first.** If a status needs a paragraph, it failed. Prefer motion, color, and icons.
2. **Physical objects, not avatars.** Marbles are opaque gem-smoke discs, not emoji or user initials.
3. **Stay above, stay small.** Never steal the screen. Default is a slim edge dock. Focus is a compact card, not a panel that covers Slack.
4. **One marble, one agent.** v1: one circle per parent session. Subagents are chips or satellites, never a second marble.
5. **Local and quiet.** No telemetry. Hooks must never block Claude Code. If Marbles is quit, agents keep working.
6. **Install is a feature.** A clever HUD that takes 30 minutes to wire is a failed product.

---

## 6. Modes

### 6.1 Default (dock)

Agents appear as a **line of 36×36 pt marbles inside a pill-shaped glass dock**. This is the idle, always-on posture.

- Marble diameter is **36pt** (Retina: 72×72 backing pixels). Hard cap; same size in Focus.
- Dock padding is **10pt** on every side of the marble.
- Reserve **4pt** between the marble and its 3-light row, then **12pt** from that row to the next marble. Lights are **3×3pt** with **1pt** gaps (row is 11pt). Item stride = **55pt**.
- Occupied dock thickness = `10 + 36 + 10` = **56pt**.
- The dock is **`NSGlassEffectView`** (`.regular`, adaptive). No extra stroke or border beyond the system glass.
- **Insertion order.** New agents append. When an agent leaves, neighbors slide closed. No sticky holes.
- **Capacity:** hard cap **50** agents (oldest insertion evicted). **9** marbles visible; after that the dock scrolls along its axis and **snaps to items**. No `+N` overflow marble.
- Autoscroll to **newly inserted** agents when not focused. Do **not** autoscroll when an agent finishes.
- Hover a marble to enter Focus. Hovering another marble switches Focus.
- The dock (glass + marbles) is the snap-friendly form: edge midpoints only (see §7).
- Empty overlay: a tiny glass pill **10×36pt** (10pt thick, 36pt along the edge), still centered on the snap midpoint.
- Clicks on the glass (not a marble) drag the dock. Clicks outside the pill pass through to the desktop.

### 6.2 Focus

Hovering a marble opens a compact HUD anchored to that marble. The dock stays visible. Marbles stay **36pt**. No dimming (a later pass will add a different highlight).

**Must show**

- The focused marble, still animating at its status speed, in the dock.
- A short preview of current work, **first matching**: (1) “Waiting for you” if `waitingOnUser`, (2) current tool line (“Editing `AuthService.swift`”) if a tool is in flight, (3) truncated latest assistant text, else (4) “Working…” / “Done” / “Something went wrong” from status.
- The same 3-light matrix stays on the marble in the dock. No icon chips on the card.
- Actions:
  - **Open Claude Code** — bring the matching Claude Code desktop session / window forward.
  - **Open Terminal** — bring the matching terminal / iTerm / Ghostty / kitty tab or pane forward when we can resolve it; otherwise open a new terminal in the session cwd.
  - **Open Conductor** — open the matching [Conductor](https://conductor.build) workspace when the session belongs to one.
- A reply composer if we can deliver a message into the live session (see §10.4). Disabled with an honest reason when we cannot.

**Must not**

- Become a second Claude Code. No full transcript, no file tree, no diff reviewer.
- Cover the whole screen. Target size: roughly a large tooltip / small popover (≤360pt wide).

**Exit:** hover off the dock and card, click outside (desktop or dock glass), or press `Esc` → Default. Hovering dock chrome or the card keeps Focus. Hovering or clicking a *different* marble **switches** Focus. Clicking the focused marble stays in Focus. Autoscroll so the focused marble stays in the 9-visible window. No dragging the dock while focused; dock glass dismisses Focus instead.

### 6.3 Mode transitions

| From | To | Trigger | Motion |
| --- | --- | --- | --- |
| Default | Focus | Hover a marble | Popover grows from that marble; 240–320ms spring |
| Focus | Focus (other) | Hover or click a different marble | Card retargets; autoscroll if needed |
| Focus | Default | Esc / click focused marble / click outside / click dock glass | Popover collapses |
| Default | Default (new snap) | Drag dock glass or a marble ≥4pt, release | Dock snaps to nearest midpoint |

Transitions must be interruptible. Hover never opens Focus from Default.

---

## 7. Placement, dragging, and snapping

The overlay is an always-on-top floating panel that joins every Space and sits above full-screen apps where the OS allows (`NSPanel` at a high window level, `canJoinAllSpaces` + `fullScreenAuxiliary`).

### 7.1 Dock snap targets

Default mode snaps to **four edge midpoints** on the current display: top, bottom, left, right. **No corners.**

Behavior:

- Drag the dock glass or a marble (not while Focused). Release always locks to the **nearest of the four midpoints**. There is no free-place rest position.
- Persist the snap point per display. Multi-monitor: the dock lives on the display it was last dropped on.
- Avoid the menu bar, Notch, Dock, and Stage Manager strip. Snap points inset by safe-area padding (~12pt).
- First launch and legacy corner values migrate to **right**.
- The pill is **always centered** on the midpoint as it grows from empty → 1 → 9 visible marbles.

### 7.2 Dock orientation

The line **orients from the locked snap point**:

| Position | Dock layout |
| --- | --- |
| Left midpoint | Vertical line, thickness grows inward (right); insertion order starts at the top |
| Right midpoint | Vertical line, thickness grows inward (left); insertion order starts at the top |
| Bottom midpoint | Horizontal line, thickness grows inward (up); insertion order starts at the left |
| Top midpoint | Horizontal line, thickness grows inward (down); insertion order starts at the left |

If the line would overflow 9 visible marbles, it scrolls along the line axis and snaps to items. It must never go off-screen without a way to reach every marble.

### 7.3 Focus anchoring

The Focus popover opens toward the interior of the screen — never off the display, never over the Notch. If the marble is on the left edge, the card opens to the right, and so on. The card attaches to the **marble**, not the pill. The dock stays pinned to the snap midpoint when the card appears.

### 7.4 Window behavior

- Clicks on marbles, dock glass, and the Focus card are interactive.
- Clicks outside the pill (Default) pass through to apps beneath.
- The app has no Dock-occupying document windows in normal use. A menu-bar extra (tiny marble or status item) is acceptable for Quit / Preferences / Install hooks.
- Hide-on-Cmd-H should *not* hide Marbles, even when Marbles is key for the Focus reply field. Provide an explicit “Hide Marbles” in the menu bar instead.

---

## 8. Visual design — gem-smoke marbles

### 8.1 North star

Each marble is an **opaque circle** whose interior is the [Paper Shaders gem-smoke](https://github.com/paper-design/shaders/blob/main/packages/shaders/src/shaders/gem-smoke.ts) field. Distortion inside the circle gives a 3D impression; there is no glass shell, no Fresnel sphere, and **no per-marble `NSGlassEffectView`**. The dock pill is the only glass.

### 8.2 Material recipe

| Layer | Look |
| --- | --- |
| Shape | Circle that **fills** the 36pt marble. Shader `scale` is unused. |
| Interior | Gem-smoke gradient (3–5 colors) swirling inside the circle. `outerGlow` is off — no smoke outside the disc. |
| Body | Opaque. `colorBack` fills any gaps in the smoke so the disc is never a see-through stamp. |
| Dock | Adaptive `NSGlassEffectView` (`.regular`). Marbles sit on the pill, not on a painted plate. |

Real-time Metal, instanced, one look at 36pt.

### 8.3 Identity — procedural generation

Marbles are **seeded**, not hand-drawn.

- Seed from a stable agent id (`session_id`, falling back to a hash of cwd + started_at).
- The same agent always gets the same marble for the life of that session, and ideally across resume.
- Diversity must be high enough that 9 agents on screen are not “nine slightly different orbs.”

Seeded uniforms (unrestricted palette for now; refine later):

| Uniform | Range | Notes |
| --- | --- | --- |
| `colors` | 3, 4, or 5 RGBA | Random RGB, alpha 1 |
| `colorBack` | RGBA | Seeded; alpha 1 so the disc is opaque |
| `colorInner` | RGBA | Seeded but unused for the interior (shader leftover; pick anything) |
| `innerDistortion` | 0.1…0.8 | Swirl strength |
| `size` | 0.7…1.0 | Smoke feature scale, not the circle |
| `angle` | 0…360° | Smoke direction |

Do not map palette → status. Palette is identity. Status is motion speed and chips (see §9).

### 8.4 Legibility on real desktops

- Marbles must remain readable on light *and* dark backgrounds (the adaptive glass dock is the backdrop).
- The dock uses system liquid glass, not a painted black plate.
- Because marbles are opaque, a pale marble still reads on a white Google Doc without a glass rim.

### 8.5 Scale

| Mode | Marble size | Notes |
| --- | --- | --- |
| Default | **36×36 pt** | Hard cap; dock padding 10pt |
| Focus | **36×36 pt** | Same size in the dock; card is separate |

Shaders must look good at 36pt. Avoid features that vanish at 36pt.

---

## 9. Motion, completion, and indicators

These rules apply in **every mode**. Default is not allowed to become a static pile that only “comes alive” after you click.

### 9.1 Agent activity → marble motion

Gem-smoke `u_time` accumulates at a **status speed**. Never reset `animationTime` to 0 when status changes — a new turn continues from the last pose.

| Agent state | Time scale |
| --- | --- |
| Working (tools in flight) | **1.5×** |
| Thinking (model inference, no current tool) | **1.5×** |
| Waiting on user / permission | **0.25×** |
| Idle, finished, error | **0.05×** |
| Reduce Motion (pref or system) | **0** — freeze the current pose |

Status chrome on the orb (freeze-as-photograph, completion bloom, error hue) is **deferred**. The 3-light matrix is the glanceable status now (see §9.3).

### 9.2 Finished — noticeable in every mode

Finished is **all three lights green** plus 0.05× smoke. Orb bloom / check-chip chrome is **deferred**. The intended later signal:

1. Motion eases to a stop.
2. A brief completion bloom: rim-light flash, a single expanding glass ring, or a caustic sweep (~400–700ms).
3. A settled “done” rest state: slightly brighter rim or a small resolved check chip that remains until the next turn or until dismissed.
4. Optional OS notification and/or a very short tactile sound, off by default or following macOS notification settings.

The completion signal must be visible when the dock is 36pt at a midpoint. If you cannot see “done” without entering Focus, it failed.

If several agents finish in a short window, stagger the blooms so the cluster does not strobe.

### 9.3 Three-light matrix

A **dot-matrix of 3 lights** sits after each marble, in Default and Focus. No SF Symbol chips.

| Spec | Value |
| --- | --- |
| Light size | **3×3pt**, corner radius **0.5pt** |
| Gap | **1pt** between lights (row length 8pt) |
| Placement | **4pt** after the marble along the dock axis, centered on the marble |
| Orientation | Across the dock axis: horizontal row on left/right, vertical column on top/bottom |
| Off | Neutral gray at **30%** opacity, no glow |
| On | `#FFFFFF` / `#00E879` / `#E84200`, plus a **4pt** outer glow at **100%** opacity in that color |

| Agent state | Lights |
| --- | --- |
| Idle | All off |
| Thinking (no current tool) | White **left → right wave** (first-to-last along the row) |
| Tool call (`currentTool` set, including a failed tool) | One **stable 1- or 2-light** subset flashes white for the whole call (HDD-style). Never all three. Never red. |
| Waiting on user | All **white** |
| Finished | All **green** |
| Session error | All **red** |

Red is reserved for a dead run the user must deal with. A failed tool stays in the white-flash vocabulary.

**Flash:** pick the subset from `session seed + tool id` so it stays put for that call. Blink ~280ms on / ~440ms off while the tool is live.

**Wave:** one white light at a time, ~640ms per step, cycling 0 → 1 → 2.

**Reduced motion:** freeze the current on-subset (wave holds light 0; flash holds the subset on; static states unchanged).

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

- Reduced motion (marble time scale 0 / freeze pose; layout snaps instead of springs)
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
- A user running ≥3 agents can identify a specific agent from the Default dock without opening Focus, in informal testing.
- Finished-state recognition from a typical viewing distance (laptop at arm’s length, dock at a midpoint) without entering Focus.
- Jump-in from Focus reaches the correct *app* ≥90% of the time; correct *session/tab* is a stretch metric.

---

## 16. Milestones

### M0 — Skeleton

- Git repo, overlay window, drag + 4-point midpoint snap.
- Three placeholder spheres, mode transitions (Default / Focus) with dummy data.

### M1 — Live agents

- Hook installer + ingest (prefs/demo UI can be a stub; polish is M4).
- One marble per live session; working vs. frozen vs. error (red hue filter).
- 3-light matrix (wave / flash / white / green / red).
- Completion bloom.

### M2 — Material

- Gem-smoke Metal renderer (opaque 36pt discs, no per-marble glass).
- Stable seeds, 3–5 color palettes, light/dark desktop legibility.

### M3 — Jump-in

- Open Claude Code / Terminal / Conductor from Focus.
- Preview of latest assistant message.
- Reply if a safe delivery path exists; otherwise honest fallback.

### M4 — Install

- Signed app, Homebrew cask (or equivalent one-liner), first-run demo marble, hook repair, uninstall.

---

## 17. Open questions

**Decided for v1** (see ARCHITECTURE.md): insertion-order dock; 9 visible then scroll; hard cap 50; no `+N`; midpoint snap only (default right); hover marble focuses; hover switches; subagents are never a second marble; no keystroke reply; demo is first-launch-only after a 2h discovery check.

Still open:

1. **Claude Code window targeting.** Depends on what the desktop app exposes (Apple Events, URL scheme, session id). May remain best-effort.
2. **Reply delivery path.** Official IPC vs Conductor only; both may be unavailable at ship.
3. **Codex / other Conductor runtimes.** Cursor Agent is in v1 via native hooks. Codex-in-Conductor is later.
4. **Notch, Stage Manager, and multiple full-screen Spaces.** Overlay policy will need device testing.
5. Refine the unrestricted gem-smoke palette.

---

## 18. Appendix A — Mode map

```text
                    hover marble
   ┌──────────┐  ───────────────►  ┌──────────┐
   │ Default  │                    │  Focus   │
   │ glass    │  ◄───────────────  │ preview  │
   │ pill dock│   Esc / outside /  │ + open   │
   └──────────┘   hover off /      └──────────┘
                  dock glass
        ▲                                 │
        │                                 │ hover/click other marble
        │  drag → snap to 4 edge midpoints│ (switches Focus)
```

Dock axis: horizontal on top/bottom edges, vertical on left/right edges. Pill always centered on the midpoint.

---

## 19. Appendix B — Visual reference notes

Source file: `documents/references/marble-visual-reference.png`.

What to steal from the frame:

- Saturated, distinct interiors so identities separate at a glance.
- Motion that feels like matter, not a spinner.

What not to steal:

- A black rectangular backdrop. Marbles sit on the glass dock.
- Using palette as a status color language. Status is speed + the 3-light matrix.
- Per-marble glass discs or a transparent “sticker” look.
- So much micro-detail that 36pt reads as noise.

---

## 20. Appendix C — Glossary

| Term | Meaning |
| --- | --- |
| Default | Pill-shaped glass dock of 36pt marbles at an edge midpoint. |
| Focus | Single-agent preview + jump-in, dock still visible. |
| Marble | One procedurally generated opaque gem-smoke disc bound to one agent. |
| Lights | 3× 3pt matrix after each marble: wave / flash / white / green / red. |
| Error hue | Full-marble red hue shift applied on crash/error; identity remains. |
| Conductor | The Mac app at conductor.build for parallel local agents in git worktrees. |
| Hook | Claude Code lifecycle callback used to stream status into Marbles. |
