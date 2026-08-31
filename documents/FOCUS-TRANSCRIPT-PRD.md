# Focus transcript — PRD

Status: **accepted** · Supersedes §12 of [ARCHITECTURE.md](ARCHITECTURE.md) on merge

## 1. Why

The Focus card today shows one line: a status word, or the current tool, or the last
assistant reply. It answers "is this agent alive" but not "what is it doing." The ask is
for the card to feel like the Claude app — the full agent transcript for the current turn,
in order, updating as the agent works, with markdown.

Every decision here is settled. §10 records what was deliberately deferred or accepted as risk.

## 2. What ships

For the **current turn only** — everything after the latest human message — the card shows,
in timestamp order:

- **Assistant prose**, markdown-rendered, in full (never truncated; the transcript scrolls)
- **Tool calls**, collapsed into runs
- **A thinking indicator** where the agent thought before acting
- **Failure and attention rows**: failed tool calls, waiting-on-you, session errors

Tool *results* are not rendered. Neither is thinking *content* — see §4.

The header stays exactly as it is now: 72pt marble, title, hairline rule, then the human's
message in its indented 8pt container. The transcript sits below it.

## 3. Non-goals

- Session scrollback. The card resets to the new turn each time the human sends.
- Tool results, diffs, or file contents.
- Syntax highlighting inside code blocks.
- A composer, or any way to reply. Focus stays read-only.
- Replacing the marble, lights, or dock behaviour.

## 4. What the data actually supports

Measured against a live 12.8 MB session (1,340 entries, 16 human turns):

| Finding | Number | Consequence |
| --- | --- | --- |
| Thinking blocks carry no text | 111 blocks, **0** non-empty — `signature` only | We can show *that* it thought, never what. The indicator is a marker, not content. |
| Turn spans are large | median **682 KB**, max **2.5 MB** | The current 256 KB tail read cannot reach a turn boundary. Drives §7. |
| Rendered payload is tiny | assistant text: median **104** chars, p90 713, max 5,263 | Once tool results are dropped, a turn renders in kilobytes. The cost is *finding* the turn, not drawing it. |
| Tool calls dominate | 238 `tool_use` in one session, 192 of them `Bash` | Collapsed runs are mandatory, not a nicety. |
| ~40% of entries are noise | `attachment` (277), `system`, `queue-operation`, `bridge-session`, `atis-latch`, `last-prompt` | Filter by `type` allowlist, not denylist. |
| Ordering is free | every entry has `timestamp`, `uuid`, `parentUuid` | Sort by timestamp; no reconstruction needed. |

Block shapes to parse, all inside `message.content[]`:

```
assistant  text       → { type: "text", text }
assistant  tool_use   → { type: "tool_use", id, name, input }
assistant  thinking   → { type: "thinking", thinking: "", signature }
user       tool_result→ { type: "tool_result", tool_use_id, content, is_error }
```

`tool_result` is read **only** for `is_error` and to mark the matching `tool_use` row
complete. Its `content` is never rendered or retained.

## 5. Layout

Width stays **360pt**. The header is unchanged. The transcript replaces today's 200pt
response region:

| | |
| --- | --- |
| Transcript max height | **320pt**, then scrolls |
| Growth | Grows with content to that cap, then scrolls |
| Follow | Pinned to the newest entry; releases when the user scrolls up, re-engages on return to the bottom |
| Row spacing | 10pt between entries; 6pt between rows inside an expanded run |

Because the card is anchored to its marble and centred on it (`LayoutEngine.cardFrame`), it
grows in **both** directions as the turn advances. Accepted for v1 — judge it in motion before
proposing a fix (§10.1).

### 5.1 Row types

**Assistant prose.** Markdown, full text, selectable. Supported: bold, italic, inline code,
bulleted and numbered lists, headings, and fenced code blocks. Code blocks get their own
background, monospaced font, and horizontal scrolling — never wrapping. No syntax colouring.

**Tool run (collapsed).** Consecutive `tool_use` blocks with no prose between them are one
row: `Ran 6 commands`. Click expands to the individual rows. The **newest run stays expanded
while it is in progress** and collapses when it completes.

**Tool call (expanded).** Verb plus target — `Read FocusCardView.swift`, `Bash ./scripts/test.sh`.
Reuse the existing verb mapping in `FocusPreview.toolLine(_:)`, which already handles Edit /
Read / Bash / Grep / WebSearch / Task and strips `mcp__` prefixes. Status is carried on the
row: in-progress → complete → failed.

**Thinking indicator.** A single muted row where one or more consecutive `thinking` blocks
occurred. No content, no expansion.

**Failure.** A tool row whose `tool_result.is_error` is true renders in the error colour with
the failure noted.

**Waiting on you.** A distinct row when status is `waitingOnUser` — the state the marble's
lights already signal, made explicit in the stream.

**Session error.** `StopFailure`, crash, or non-zero exit renders as a terminal row so the
turn visibly ends badly rather than just stopping.

### 5.2 Empty state

Before the first step lands, the transcript area shows the existing status word from
`FocusPreview.statusWord(_:)` — "Thinking…" — as its only entry. It is replaced by real
entries as they arrive. This is continuous with what ships today.

## 6. Interaction

- **Hover behaviour is unchanged.** Hover a marble to open, move into the card to keep it
  open, leave to dismiss. No pinning, no click-to-open. The existing `hoverMargin` and
  `hoverBridgeContains` logic carries over untouched.
- **All text is selectable and copyable** — prose and code alike.
- Two conflicts fall out of that and must be handled:
  1. A drag beginning inside the transcript must select text, **not** drag the dock. The drag
     arming in `OverlayController.handleMouseDown` currently fires on `.dock` and `.marble`;
     `.card` already passes the event through, so transcript drags are safe — but this must
     be tested against the drag work just landed.
  2. Hover-off must not fire mid-selection. `handleHover` already bails while a mouse button
     is down (`NSEvent.pressedMouseButtons == 0`), which covers it.
- Esc dismisses, as today.

## 7. Liveness and performance

**Refresh model: live only while the card is open.** A file-system source watches the session
jsonl while a card is open for that agent; otherwise refresh stays hook-driven as it is now.

The naive implementation — re-read and re-parse on every change — is not viable at 12.8 MB
with sub-second updates. The model is incremental:

1. **Cold start** (card opens): scan backward for the last human turn. Worst observed
   distance is 2.5 MB, so this must not be capped at 256 KB the way `TranscriptPeek.tailData`
   is today. Parse forward from there, build the turn model, record the byte offset of EOF.
2. **On change**: read only from the recorded offset to the new EOF, parse the new lines,
   append to the model, update the offset. Cost is O(new bytes).
3. **On a new human turn**: discard the model and restart it at that entry.
4. **On close**: tear the watcher down.

Caps: parse at most 2,000 entries per turn and 512 KB of *retained* text; beyond that, drop
the oldest entries and mark the stream truncated at the top. Tool result content is discarded
at parse time and never retained, which is what makes these numbers small.

**Measured** (step 1 shipped, against three real sessions):

| | 13 MB session | 1 MB session |
| --- | --- | --- |
| Cold load | **8.6 ms** | 2.0 ms |
| Incremental refresh | **0.04 ms** | 0.05 ms |
| Retained prose for the turn | < 1 KB | < 1 KB |

Two decisions got it there, both worth keeping. The boundary scan walks **backwards** and stops
at the first hit rather than scanning the window forwards for the last one — that alone was
77 ms → 15 ms, because the forward scan JSON-parses every line in the window. And the lookback
**widens progressively** (256 KB → 1 MB → 4 MB → 8 MB) instead of reading the budget up front,
since the boundary is usually near EOF — 15 ms → 8.6 ms.

## 8. Fallbacks

| Case | Behaviour |
| --- | --- |
| Cursor-sourced agent | No jsonl exists under `~/.claude/projects`. Falls back to today's single-line `FocusPreview.line(for:)`. Deferred (§10.2). |
| Transcript unreadable or missing | Same single-line fallback. Never show an empty card. |
| Demo / injected marble | Static canned transcript so the shape is visible without a live agent. Keeps the "Demo." title. |
| Turn with no steps yet | §5.2 empty state. |
| Subagent (`isSidechain`) entries | Not nested — settled. The parent's `Agent`/`Task` tool row is all that shows; what the subagent did is out of scope. |

## 9. Implementation

Ordered so each step is independently shippable and visually checkable.

1. **Parse** — `TranscriptTurn` model plus a `TranscriptReader` that does the backward scan,
   incremental forward read, and noise filtering. Pure and testable; goes in the `test.sh`
   source list. No UI.
2. **Static render** — replace the response `NSTextView` with a stack of row views driven by
   the model. Plain text only, no markdown. Proves layout, sizing, and scrolling.
3. **Markdown** — inline attributes via `NSAttributedString(markdown:)`, then a small block
   parser for lists, headings, and fenced code. `FocusCardMetrics` grows a per-row measurement
   function; the card's height stays the sum of its rows so measured and drawn geometry cannot
   drift, as now.
4. **Collapsed runs** — grouping, expansion state, and the newest-run-open rule.
5. **Liveness** — `DispatchSource` watcher, incremental reads, follow-the-newest scrolling.
6. **Failure and attention rows** — wire `is_error`, `waitingOnUser`, and session-error states.

Files most affected: `Sources/Focus/` (new `TranscriptReader`, `TranscriptTurn`, row views,
markdown renderer), `Sources/Agents/TranscriptPeek.swift` (the backward scan generalises what
`latestExchange` does today), `Sources/Focus/FocusCardMetrics.swift`, `FocusCardView.swift`.

## 10. Resolved, deferred, and accepted

All questions from the draft are closed. Two carry risk into v1 deliberately.

**10.1 — Growth in both directions: accepted, revisit after seeing it.** The card is centred on
its marble, so growing to the 320pt cap pushes it outward top and bottom while you watch.
Shipping it this way rather than fixing the viewport at full height, because the jitter may
well be fine and the fixed alternative wastes space on short turns. Judge it once step 2 of §9
runs; if it reads badly, the fix is a fixed-height viewport, not a new layout model.

**10.2 — Cursor sessions: deferred.** Cursor-sourced agents keep today's single-line preview.
No Cursor reader in v1. Roughly half the app's supported sources therefore get none of this,
which is a known and accepted gap.

**10.3 — Subagents: settled, not shown.** A `Task`/`Agent` call is one tool row. Sidechain
entries are filtered out entirely.

**10.4 — Retention: settled, memory only.** The turn model never touches disk, consistent with
§13 of ARCHITECTURE.md. Nothing persists across launches.

**10.5 — Numbers: settled.** Transcript cap **320pt**. Row spacing 10pt, 6pt inside an expanded
run. Parse caps 2,000 entries and 512 KB retained text per turn.

## 11. Testing

`scripts/test.sh` compiles a hand-maintained source list and excludes the view layer, so:

- **In the test target**: turn-boundary detection, noise filtering, block parsing, run
  grouping, incremental-append correctness, cap enforcement, markdown block parsing, and
  per-row measurement. Fixtures go in `Tests/Fixtures/transcripts/`, captured from real
  sessions and trimmed.
- **Not in the test target**: row views, the watcher, scrolling. Verified by hand.

Manual gate, per §16.1 of ARCHITECTURE.md: hover an agent mid-turn and watch steps land;
confirm the newest stays visible; scroll up and confirm follow releases; send a new message
and confirm the transcript resets; select and copy from a code block; confirm the dock still
drags from the marble with the card open.
