import Foundation

struct TranscriptSnapshot: Equatable {
    var hasConversation: Bool
    var title: String?

    static let empty = TranscriptSnapshot(hasConversation: false, title: nil)
}

enum TranscriptPeek {
    private static let headLimit = 128 * 1024
    private static let tailLimit = 256 * 1024
    private static let maxTitle = 80

    static func inspect(path: String?) -> TranscriptSnapshot {
        guard let path, !path.isEmpty else { return .empty }
        guard let handle = FileHandle(forReadingAtPath: path) else { return .empty }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: headLimit)
        return inspect(data: data)
    }

    static func inspect(data: Data) -> TranscriptSnapshot {
        var title: String?
        var hasUser = false
        guard let text = String(data: data, encoding: .utf8) else { return .empty }
        text.enumerateLines { line, _ in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return
            }
            let type = obj["type"] as? String
            if type == "custom-title", let value = string(obj["customTitle"] ?? obj["title"]) {
                title = truncate(value)
            }
            if type == "agent-name", title == nil, let value = string(obj["agentName"]) {
                title = truncate(value)
            }
            if type == "user" {
                hasUser = true
                if title == nil, let value = userText(obj) {
                    title = truncate(value)
                }
            }
        }
        return TranscriptSnapshot(hasConversation: hasUser || title != nil, title: title)
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
