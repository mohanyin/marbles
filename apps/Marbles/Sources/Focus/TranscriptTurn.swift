import Foundation

/// One thing the agent did, in the order it happened.
enum TranscriptEntry: Equatable {
    case prose(String)
    case tool(TranscriptToolCall)
    /// The agent thought before acting. Content is never available — see PRD §4.
    case thinking
}

struct TranscriptToolCall: Equatable {
    enum Status: Equatable {
        case running
        case succeeded
        case failed
    }

    var id: String
    var name: String
    /// Short summary of the input — a file's basename, the head of a command.
    var target: String?
    var status: Status = .running

    /// Row copy: verb plus target, e.g. `Read FocusCardView.swift`.
    var label: String {
        let verb = TranscriptToolCall.displayName(name)
        guard let target, !target.isEmpty else { return verb }
        return "\(verb) \(target)"
    }

    static func displayName(_ name: String) -> String {
        guard name.hasPrefix("mcp__") else { return name }
        return name.split(separator: "_").last.map(String.init) ?? name
    }
}

/// Consecutive entries grouped for display: tool calls with no prose between them collapse
/// into one run (PRD §5.1).
enum TranscriptRun: Equatable {
    case prose(String)
    case thinking
    case tools([TranscriptToolCall])
}

/// The current turn — the human's message and everything the agent has done since.
struct TranscriptTurn: Equatable {
    var prompt: String?
    var entries: [TranscriptEntry] = []
    /// Oldest entries were dropped to stay under the caps; the stream is incomplete at the top.
    var truncatedAtTop = false

    static let empty = TranscriptTurn()

    var isEmpty: Bool { prompt == nil && entries.isEmpty }

    /// Newest assistant prose in the turn — the one-line preview the card falls back to.
    var latestProse: String? {
        for entry in entries.reversed() {
            if case .prose(let text) = entry { return text }
        }
        return nil
    }

    var runs: [TranscriptRun] {
        var out: [TranscriptRun] = []
        for entry in entries {
            switch entry {
            case .prose(let text):
                out.append(.prose(text))
            case .thinking:
                // Consecutive thinking blocks are one marker.
                if case .thinking = out.last {} else { out.append(.thinking) }
            case .tool(let call):
                if case .tools(var calls) = out.last {
                    calls.append(call)
                    out[out.count - 1] = .tools(calls)
                } else {
                    out.append(.tools([call]))
                }
            }
        }
        return out
    }
}

/// Which tool runs are open.
///
/// The default is the PRD's rule — the newest run stays expanded while it is still working — but
/// a click overrides it in either direction, and that override has to survive the rebuilds that
/// every refresh triggers. Runs are keyed by their first tool call's id, which is stable for the
/// life of the turn.
struct TranscriptExpansion: Equatable {
    private var opened: Set<String> = []
    private var closed: Set<String> = []

    static func key(_ calls: [TranscriptToolCall]) -> String? { calls.first?.id }

    func isExpanded(_ calls: [TranscriptToolCall], isLast: Bool) -> Bool {
        guard let key = Self.key(calls) else { return false }
        if opened.contains(key) { return true }
        if closed.contains(key) { return false }
        return isLast && calls.contains { $0.status == .running }
    }

    mutating func toggle(_ calls: [TranscriptToolCall], isLast: Bool) {
        guard let key = Self.key(calls) else { return }
        if isExpanded(calls, isLast: isLast) {
            opened.remove(key)
            closed.insert(key)
        } else {
            closed.remove(key)
            opened.insert(key)
        }
    }

    /// A new turn clears every override — the ids are gone anyway.
    mutating func reset() {
        opened = []
        closed = []
    }
}

/// Incremental line-by-line parser over a Claude Code session jsonl.
///
/// Feed it bytes with `consume`; it keeps only the current turn. A new human message resets the
/// turn, which is what scopes the card to "this question" (PRD §2). Tool *results* are read only
/// to resolve a call's status and are never retained (PRD §4) — that is what keeps a 12 MB
/// session's rendered payload in the kilobytes.
struct TranscriptParser {
    /// Entry ceiling per turn; oldest are dropped past this (PRD §7).
    static let maxEntries = 2_000
    /// Retained prose ceiling per turn, in UTF-8 bytes.
    static let maxRetainedText = 512 * 1024

    private(set) var turn = TranscriptTurn.empty
    /// Bytes after the last newline — a partial line awaiting the rest of the file.
    private var pending = Data()

    init() {}

    /// Returns true when the turn changed.
    @discardableResult
    mutating func consume(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        pending.append(data)
        var changed = false
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<newline]
            pending = Data(pending[(newline + 1)...])
            if consume(line: Data(line)) { changed = true }
        }
        if changed { enforceCaps() }
        return changed
    }

    /// The stream is missing entries at the top — either capped, or the turn boundary was
    /// beyond the reader's lookback budget.
    mutating func markTruncated() {
        turn.truncatedAtTop = true
    }

    /// Flush a trailing line with no newline — the last record of a file that ends mid-write.
    @discardableResult
    mutating func flush() -> Bool {
        guard !pending.isEmpty else { return false }
        let line = pending
        pending = Data()
        let changed = consume(line: line)
        if changed { enforceCaps() }
        return changed
    }

    // MARK: - Line handling

    private mutating func consume(line: Data) -> Bool {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return false }
        // Subagent work is out of scope — the parent's Task row is all that shows (PRD §10.3).
        if obj["isSidechain"] as? Bool == true { return false }

        // Allowlist: everything else in the file is scaffolding (attachment, system,
        // queue-operation, bridge-session, atis-latch, last-prompt, custom-title).
        let type = obj["type"] as? String
        guard type == "user" || type == "assistant" else { return false }

        let message = obj["message"] as? [String: Any]
        let role = (message?["role"] as? String) ?? type

        if role == "user" {
            return consumeUser(message: message, fallback: obj)
        }
        return consumeAssistant(message: message)
    }

    private mutating func consumeUser(message: [String: Any]?, fallback: [String: Any]) -> Bool {
        let content = message?["content"] ?? fallback["content"]

        if let text = content as? String {
            guard let human = Self.humanText(text) else { return false }
            startTurn(prompt: human)
            return true
        }

        guard let blocks = content as? [[String: Any]] else { return false }

        // A user entry is either a real human turn or a batch of tool results, never both.
        let texts = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
        if !texts.isEmpty, let human = Self.humanText(texts.joined(separator: "\n")) {
            startTurn(prompt: human)
            return true
        }

        var changed = false
        for block in blocks where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String else { continue }
            let failed = (block["is_error"] as? Bool) ?? false
            if resolve(toolID: id, failed: failed) { changed = true }
        }
        return changed
    }

    private mutating func consumeAssistant(message: [String: Any]?) -> Bool {
        guard let content = message?["content"] else { return false }

        if let text = content as? String {
            return appendProse(text)
        }
        guard let blocks = content as? [[String: Any]] else { return false }

        var changed = false
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, appendProse(text) { changed = true }
            case "thinking":
                turn.entries.append(.thinking)
                changed = true
            case "tool_use":
                guard let id = block["id"] as? String else { continue }
                let name = (block["name"] as? String) ?? "Tool"
                turn.entries.append(.tool(TranscriptToolCall(
                    id: id,
                    name: name,
                    target: HookMapper.toolSummary(name: name, input: block["input"])
                )))
                changed = true
            default:
                continue
            }
        }
        return changed
    }

    // MARK: - Mutation

    private mutating func startTurn(prompt: String) {
        turn = TranscriptTurn(prompt: prompt, entries: [], truncatedAtTop: false)
    }

    private mutating func appendProse(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        turn.entries.append(.prose(trimmed))
        return true
    }

    private mutating func resolve(toolID: String, failed: Bool) -> Bool {
        for index in turn.entries.indices.reversed() {
            guard case .tool(var call) = turn.entries[index], call.id == toolID else { continue }
            let next: TranscriptToolCall.Status = failed ? .failed : .succeeded
            guard call.status != next else { return false }
            call.status = next
            turn.entries[index] = .tool(call)
            return true
        }
        return false
    }

    private mutating func enforceCaps() {
        if turn.entries.count > Self.maxEntries {
            turn.entries.removeFirst(turn.entries.count - Self.maxEntries)
            turn.truncatedAtTop = true
        }
        var bytes = 0
        for entry in turn.entries.reversed() {
            if case .prose(let text) = entry { bytes += text.utf8.count }
        }
        guard bytes > Self.maxRetainedText else { return }
        // Drop oldest prose until back under the ceiling; tool rows are cheap, keep them.
        var index = turn.entries.startIndex
        while bytes > Self.maxRetainedText, index < turn.entries.endIndex {
            if case .prose(let text) = turn.entries[index] {
                bytes -= text.utf8.count
                turn.entries.remove(at: index)
                turn.truncatedAtTop = true
                continue
            }
            index += 1
        }
    }

    // MARK: - Helpers

    /// A human turn is plain text the person typed. Tool results carry no `text` block, and
    /// `<…>`-wrapped scaffolding (command output, system reminders) is not a human message.
    static func humanText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return nil }
        if trimmed.count <= IngestConstants.previewLimit { return trimmed }
        return String(trimmed.prefix(IngestConstants.previewLimit - 1)) + "…"
    }

    /// True when a raw jsonl line opens a new human turn. Used by the backward scan.
    static func isHumanTurn(line: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["isSidechain"] as? Bool != true,
              obj["type"] as? String == "user"
        else { return false }
        let message = obj["message"] as? [String: Any]
        let content = message?["content"] ?? obj["content"]
        if let text = content as? String { return humanText(text) != nil }
        guard let blocks = content as? [[String: Any]] else { return false }
        let texts = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
        return !texts.isEmpty && humanText(texts.joined(separator: "\n")) != nil
    }
}
