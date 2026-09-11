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

    /// The `cwd` a transcript records for itself. Discovery matches this against a live process's
    /// working directory; the encoded folder name cannot be decoded back because it maps both
    /// slashes and dots onto dashes.
    static func recordedCWD(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let text = String(data: handle.readData(ofLength: 64 * 1024), encoding: .utf8) else {
            return nil
        }
        var found: String?
        text.enumerateLines { line, stop in
            guard line.contains("\"cwd\""),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let cwd = obj["cwd"] as? String, !cwd.isEmpty
            else { return }
            found = cwd
            stop = true
        }
        return found
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
///
/// The result is a label, not a sentence: "Fix merge conflicts", not "fix the merge conflicts on
/// the PR so that CI goes green". A prompt states a task at whatever length it takes; a card has
/// room for a few words. `condense` keeps the opening verb and its object and drops the rest.
enum TitleSummary {
    static let maxLength = 60
    /// Words kept after condensing. Four fits the card at `FocusCardMetrics.titleFont` without
    /// truncating, and is long enough for "Add dark mode to settings".
    static let maxWords = 4

    private static let noise: [NSRegularExpression] = [
        #"https?://\S+"#,
        #"\[Image[^\]]*\]"#,
        #"`[^`]*`"#,
        #"@\S+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Conversational lead-ins that carry no information about the task.
    private static let leadIns: [NSRegularExpression] = [
        #"^(hey|hi|hello|yo|ok|okay|so|also|now|please|pls|plz|thanks)[,!.\s]+"#,
        #"^(can|could|would|will|do)\s+(you|u|we|i)\s+(please\s+|pls\s+)?"#,
        #"^(should|shall)\s+(you|we|i)\s+"#,
        #"^(please|pls|plz)\s+"#,
        #"^(help me|i want you to|i need you to|i'd like you to|i would like you to|i want to|i need to|i'd like to|let's|lets)\s+"#,
        // "go ahead and fix X", "try to fix X" — the real verb is the one after.
        #"^(go ahead and|try to|attempt to|make sure to|see if you can)\s+"#,
        // "why is X broken" / "how come X fails" — the question word is not the subject.
        #"^(why|how come|what's up with|whats up with|any idea why|do you know why)\s+"#,
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
        return clip(capitalized(condense(sentence)))
    }

    /// Cuts a task statement down to its head phrase.
    ///
    /// Two passes. First a clause break — "so that", "because", "and then" and friends introduce
    /// rationale or a second task, and everything from there on is detail the card does not need.
    /// Then a word cap, which also drops a dangling function word so the label does not end on
    /// "to" or "the".
    private static func condense(_ sentence: String) -> String {
        var words = clauseHead(sentence).split(separator: " ").map(String.init)
        words = Array(words.prefix(cut(words)))
        while let last = words.last, words.count > 1, danglers.contains(last.lowercased()) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// How many words to keep. `maxWords` is the target, but a cut landing inside a phrase reads
    /// worse than a slightly longer label: "Add a preference" loses the point that
    /// "Add a preference to disable sound" makes. So the cap slides to the nearest phrase
    /// boundary — the start of a trailing prepositional phrase, or the end of one just past it.
    private static func cut(_ words: [String]) -> Int {
        guard words.count > maxWords else { return words.count }
        // A preposition inside the budget starts a phrase; keeping it means keeping its object,
        // which is allowed to run one word past the cap.
        for index in stride(from: maxWords - 1, through: 2, by: -1)
        where prepositions.contains(words[index].lowercased()) {
            return min(words.count, index + 3) > maxWords + 2 ? index : min(words.count, index + 3)
        }
        // Otherwise take one more word when the cap splits a noun phrase off its head noun.
        if words.count > maxWords, danglers.contains(words[maxWords - 1].lowercased()) {
            return maxWords + 1
        }
        return maxWords
    }

    /// Prepositions that open a trailing phrase worth keeping whole.
    private static let prepositions: Set<String> = ["to", "for", "in", "on", "into", "from", "with", "of"]


    /// Everything before the first clause break, when one leaves at least a verb and an object.
    private static func clauseHead(_ sentence: String) -> String {
        let lower = sentence.lowercased()
        var cut = sentence.endIndex
        for marker in clauseBreaks {
            guard let found = lower.range(of: " \(marker) ") else { continue }
            let head = sentence[..<found.lowerBound]
            guard head.split(separator: " ").count >= 2, found.lowerBound < cut else { continue }
            cut = found.lowerBound
        }
        return String(sentence[..<cut])
    }

    /// Clause openers that mark the start of rationale, conditions, or a follow-on task.
    private static let clauseBreaks = [
        "so that", "so", "because", "since", "such that", "in order to",
        "and then", "then", "and also", "also", "but", "while", "which", "that should",
        "if", "when", "where", "as well as", "plus",
    ]

    /// Function words that read as unfinished at the end of a label. Pronouns are absent on
    /// purpose: in "Ship it" or "Fix that" they are the object, and trimming them strands the verb.
    private static let danglers: Set<String> = [
        "to", "the", "a", "an", "of", "for", "in", "on", "at", "with", "from", "into",
        "and", "or", "by", "as", "my", "our", "its",
    ]

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

    /// Renders a slug-shaped title as prose: `cleanup-stale-drafts-scheduled` reads as
    /// "Cleanup stale drafts scheduled".
    ///
    /// Claude Code normally writes a prose `ai-title`, but a session that takes on a named task
    /// gets re-badged with that task's identifier, which is a slug. Only the display is changed —
    /// the transcript keeps whatever it recorded, and jump-in still matches on the raw value.
    ///
    /// Deliberately conservative, because several things that look slug-adjacent are not slugs:
    /// a filename (`install.sh`) is left alone, as is anything containing whitespace, a path
    /// separator, or uppercase — a real title like `Mikaela/asana-…-social-share Easter egg`
    /// must survive untouched.
    static func prettifySlug(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return title }
        // Prose, paths and filenames are not slugs. A dot rules out `install.sh` and `v2.1.3`.
        guard !trimmed.contains(where: { $0.isWhitespace }),
              !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains(".")
        else { return title }
        // Uppercase means someone already chose the casing (`WEB-285`, `Asana-Sync`).
        guard trimmed == trimmed.lowercased() else { return title }
        let separators: Set<Character> = ["-", "_"]
        guard trimmed.contains(where: { separators.contains($0) }) else { return title }
        let words = trimmed.split(whereSeparator: { separators.contains($0) }).map(String.init)
        // A single word plus stray dashes ("--fix") is not a slug worth rewriting.
        guard words.count >= 2, words.allSatisfy({ !$0.isEmpty }) else { return title }
        return capitalized(issueKeyed(words).joined(separator: " "))
    }

    /// Rejoins a leading issue key that the separator split apart, so `web-407-…` keeps the
    /// `WEB-407` an issue tracker would show rather than becoming "Web 407".
    private static func issueKeyed(_ words: [String]) -> [String] {
        guard words.count >= 2,
              knownTrackers.contains(words[0]),
              words[1].allSatisfy(\.isNumber)
        else { return words.map(ticketCased) }
        return [words[0].uppercased() + "-" + words[1]] + words.dropFirst(2)
    }

    /// Keeps issue keys readable: the `web` in `web-407-customer-story-date` is a tracker prefix,
    /// not a word, so it is upper-cased rather than title-cased.
    private static func ticketCased(_ word: String) -> String {
        word.count <= 3 && word.allSatisfy(\.isLetter) && knownTrackers.contains(word)
            ? word.uppercased()
            : word
    }

    /// Issue-tracker prefixes seen in these titles. Kept explicit so ordinary short words
    /// ("add", "fix", "the") are never shouted.
    private static let knownTrackers: Set<String> = ["web", "eng", "ops", "inf", "sec", "ds", "ml"]
}
