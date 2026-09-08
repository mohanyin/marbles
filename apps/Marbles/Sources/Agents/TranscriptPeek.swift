import Foundation

struct TranscriptSnapshot: Equatable {
    /// Where the title came from, weakest first. A stronger source always replaces a weaker one;
    /// within a source the newest record wins.
    enum TitleSource: Int, Comparable {
        case none, prompt, agentName, ai, custom

        static func < (lhs: TitleSource, rhs: TitleSource) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var hasConversation: Bool
    var title: String?
    var titleSource: TitleSource = .none

    static let empty = TranscriptSnapshot(hasConversation: false, title: nil)
}

enum TranscriptPeek {
    private static let headLimit = 128 * 1024
    private static let tailLimit = 256 * 1024
    private static let maxTitle = 80

    /// Title preference: a `/rename` (`custom-title`) beats Claude Code's generated `ai-title`,
    /// which beats a subagent name, which beats a summary squeezed out of the first prompt.
    /// The head of the file carries the prompt; the generated title is written after the first
    /// reply and regenerated as the session goes, so the tail is consulted for the newest one.
    static func inspect(path: String?) -> TranscriptSnapshot {
        guard let path, !path.isEmpty else { return .empty }
        guard let handle = FileHandle(forReadingAtPath: path) else { return .empty }
        defer { try? handle.close() }
        var snapshot = inspect(data: handle.readData(ofLength: headLimit))
        if snapshot.titleSource < .custom, let tail = tailData(handle: handle) {
            let late = inspect(data: tail)
            // A later prompt is not the first ask; anything stronger from the tail is newer.
            if late.titleSource > .prompt, late.titleSource >= snapshot.titleSource {
                snapshot.title = late.title
                snapshot.titleSource = late.titleSource
            }
        }
        return snapshot
    }

    static func inspect(data: Data) -> TranscriptSnapshot {
        var snapshot = TranscriptSnapshot.empty
        var hasUser = false
        guard let text = String(data: data, encoding: .utf8) else { return .empty }
        func offer(_ value: String, from source: TranscriptSnapshot.TitleSource) {
            guard source >= snapshot.titleSource else { return }
            snapshot.title = truncate(value)
            snapshot.titleSource = source
        }
        text.enumerateLines { line, _ in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return
            }
            switch obj["type"] as? String {
            case "custom-title":
                if let value = string(obj["customTitle"] ?? obj["title"]) { offer(value, from: .custom) }
            case "ai-title":
                if let value = string(obj["aiTitle"] ?? obj["title"]) { offer(value, from: .ai) }
            case "agent-name":
                if let value = string(obj["agentName"]) { offer(value, from: .agentName) }
            case "user":
                hasUser = true
                if snapshot.titleSource == .none, let value = userText(obj),
                   let summary = TitleSummary.make(from: value) {
                    offer(summary, from: .prompt)
                }
            default:
                break
            }
        }
        snapshot.hasConversation = hasUser || snapshot.title != nil
        return snapshot
    }

    /// Claude Code's auto-generated conversation title — the same text it writes into the
    /// terminal tab title, so jump-in can pick the right tab among several in one directory.
    /// Newest wins; the tail is scanned first because the title is regenerated as the session goes.
    static func latestAITitle(path: String?) -> String? {
        if let tail = tailData(path: path), let title = latestAITitle(data: tail) {
            return title
        }
        guard let path, !path.isEmpty, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return latestAITitle(data: handle.readData(ofLength: headLimit))
    }

    static func latestAITitle(data: Data) -> String? {
        var latest: String?
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        text.enumerateLines { line, _ in
            guard line.contains("ai-title"),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "ai-title",
                  let value = string(obj["aiTitle"] ?? obj["title"])
            else { return }
            latest = value
        }
        return latest
    }

    /// Latest visible assistant reply (text blocks only — not thinking).
    static func latestAssistantText(path: String?) -> String? {
        tailData(path: path).flatMap(latestAssistantText(data:))
    }

    /// Latest human turn. Tool results and `<…>`-wrapped scaffolding are skipped by `userText`.
    static func latestUserText(path: String?) -> String? {
        tailData(path: path).flatMap(latestUserText(data:))
    }

    static func latestUserText(data: Data) -> String? {
        var latest: String?
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        text.enumerateLines { line, _ in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return
            }
            let type = obj["type"] as? String
            let role = (obj["message"] as? [String: Any])?["role"] as? String
            if obj["isSidechain"] as? Bool == true { return }
            guard type == "user" || role == "user" else { return }
            if let value = userText(obj) {
                latest = cap(value)
            }
        }
        return latest
    }

    /// Last `tailLimit` bytes, minus the leading partial line.
    private static func tailData(path: String?) -> Data? {
        guard let path, !path.isEmpty else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return tailData(handle: handle)
    }

    private static func tailData(handle: FileHandle) -> Data? {
        let size = handle.seekToEndOfFile()
        let start = size > UInt64(tailLimit) ? size - UInt64(tailLimit) : 0
        handle.seek(toFileOffset: start)
        var data = handle.readDataToEndOfFile()
        if start > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = Data(data[(newline + 1)...])
        }
        return data
    }

    static func latestAssistantText(data: Data) -> String? {
        var latest: String?
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        text.enumerateLines { line, _ in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return
            }
            let type = obj["type"] as? String
            let role = (obj["message"] as? [String: Any])?["role"] as? String
            if obj["isSidechain"] as? Bool == true { return }
            guard type == "assistant" || role == "assistant" else { return }
            if let value = assistantText(obj) {
                latest = value
            }
        }
        return latest
    }

    static func resolvedPath(sessionID: String, cwd: String?, explicit: String?) -> String? {
        var candidates: [String] = []
        if let explicit, !explicit.isEmpty {
            candidates.append((explicit as NSString).expandingTildeInPath)
        }
        if let cwd, !cwd.isEmpty {
            let normalized = URL(fileURLWithPath: cwd).standardizedFileURL.path
            let encoded = normalized.replacingOccurrences(of: "/", with: "-")
            candidates.append(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/projects/\(encoded)/\(sessionID).jsonl")
                    .path
            )
        }
        if let hit = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0) }) {
            return hit
        }
        if let hit = locateBySessionID(sessionID) {
            return hit
        }
        return candidates.first
    }

    private static func locateBySessionID(_ sessionID: String) -> String? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for dir in dirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let file = dir.appendingPathComponent("\(sessionID).jsonl").path
            if FileManager.default.isReadableFile(atPath: file) {
                return file
            }
        }
        return nil
    }

    private static func userText(_ obj: [String: Any]) -> String? {
        let message = obj["message"] as? [String: Any]
        let raw: String?
        if let text = string(message?["content"]) {
            raw = text
        } else if let blocks = message?["content"] as? [[String: Any]] {
            raw = blocks.compactMap { string($0["text"]) }.joined(separator: " ")
        } else {
            raw = string(obj["content"])
        }
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("<") { return nil }
        return trimmed
    }

    private static func assistantText(_ obj: [String: Any]) -> String? {
        let message = obj["message"] as? [String: Any]
        let raw: String?
        if let text = string(message?["content"]) {
            raw = text
        } else if let blocks = message?["content"] as? [[String: Any]] {
            let parts = blocks.compactMap { block -> String? in
                if let type = block["type"] as? String, type == "thinking" { return nil }
                return string(block["text"])
            }
            raw = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        } else {
            raw = string(obj["content"])
        }
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return cap(trimmed)
    }

    private static func cap(_ text: String) -> String {
        if text.count <= IngestConstants.previewLimit { return text }
        return String(text.prefix(IngestConstants.previewLimit - 1)) + "…"
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncate(_ text: String) -> String {
        if text.count <= maxTitle { return text }
        return String(text.prefix(maxTitle - 1)) + "…"
    }
}

/// Squeezes a card title out of the first prompt for sessions that have no generated title yet
/// (the first seconds of a Claude Code session, or Cursor, which never writes one).
enum TitleSummary {
    static let maxLength = 60

    private static let noise: [NSRegularExpression] = [
        #"https?://\S+"#,
        #"\[Image[^\]]*\]"#,
        #"`[^`]*`"#,
        #"@\S+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Conversational lead-ins that carry no information about the task.
    private static let leadIns: [NSRegularExpression] = [
        #"^(hey|hi|hello|yo|ok|okay|so|also|now|please|pls|plz|thanks)[,!.\s]+"#,
        #"^(can|could|would|will|do)\s+(you|u)\s+(please\s+|pls\s+)?"#,
        #"^(please|pls|plz)\s+"#,
        #"^(help me|i want you to|i need you to|i'd like you to|i would like you to|i want to|i need to|i'd like to|let's|lets)\s+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func make(from prompt: String) -> String? {
        var text = prompt
        for pattern in noise {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        guard let line = text.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return fallback(prompt) }
        var sentence = firstSentence(line)
        var stripped = true
        while stripped {
            stripped = false
            for pattern in leadIns {
                let range = NSRange(sentence.startIndex..., in: sentence)
                if let match = pattern.firstMatch(in: sentence, range: range), let r = Range(match.range, in: sentence) {
                    sentence.removeSubrange(r)
                    stripped = true
                }
            }
        }
        sentence = sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!:;,-–— "))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard sentence.count >= 3 else { return fallback(prompt) }
        return clip(capitalized(sentence))
    }

    private static func firstSentence(_ line: String) -> String {
        var end = line.endIndex
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            let next = line.index(after: index)
            if ch == "." || ch == "?" || ch == "!" || ch == ":" || ch == ";" {
                if next == line.endIndex || line[next].isWhitespace {
                    end = index
                    break
                }
            }
            index = next
        }
        return String(line[..<end])
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func clip(_ text: String) -> String {
        if text.count <= maxLength { return text }
        let head = String(text.prefix(maxLength))
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > maxLength / 2 {
            return String(head[..<space]).trimmingCharacters(in: CharacterSet(charactersIn: ".?!:;,-–— ")) + "…"
        }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    private static func fallback(_ prompt: String) -> String? {
        let line = prompt.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line, !line.isEmpty else { return nil }
        return clip(capitalized(line))
    }
}
