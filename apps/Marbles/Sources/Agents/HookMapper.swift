import Foundation

enum HookMapper {
    static func event(from data: Data) -> HookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let obj = object as? [String: Any] else { return nil }
        if truthy(obj["parseError"]) { return nil }

        let name = string(obj, "hook_event_name", "hookEventName") ?? ""
        if isIgnored(name) { return nil }

        let cursor = isCursor(obj, name: name)
        if cursor {
            let mode = string(obj, "composer_mode", "composerMode")
            if mode == "ask" || mode == "edit" { return nil }
        }

        guard let sessionID = string(obj, "session_id", "sessionID", "conversation_id", "conversationId"),
              !sessionID.isEmpty
        else { return nil }

        let toolName = mappedToolName(string(obj, "tool_name", "toolName"))
        let toolInput = obj["tool_input"] ?? obj["toolInput"]
        let text = string(obj, "last_assistant_message", "lastAssistantMessage", "text")

        return HookEvent(
            hookEventName: name,
            sessionID: sessionID,
            cwd: string(obj, "cwd"),
            transcriptPath: string(obj, "transcript_path", "transcriptPath"),
            toolName: toolName,
            toolInputSummary: toolSummary(name: toolName, input: toolInput),
            lastAssistantMessage: text.map { String($0.prefix(IngestConstants.previewLimit)) },
            notificationType: string(obj, "notification_type", "notificationType", "type"),
            agentID: string(obj, "agent_id", "agentID"),
            agentType: string(obj, "agent_type", "agentType"),
            sessionEndReason: string(obj, "reason", "sessionEndReason"),
            sessionStartSource: string(obj, "source", "sessionStartSource", "matcher"),
            composerMode: string(obj, "composer_mode", "composerMode"),
            isBackgroundAgent: bool(obj, "is_background_agent", "isBackgroundAgent"),
            stopStatus: string(obj, "status", "stopStatus"),
            sourceHint: cursor ? .cursor : sourceHint(obj),
            parseError: false
        )
    }

    private static func isIgnored(_ name: String) -> Bool {
        ["tab", "Tab", "workspaceOpen", "afterTabFileEdit"].contains(name)
    }

    private static func isCursor(_ obj: [String: Any], name: String) -> Bool {
        if obj["cursor_version"] != nil || obj["cursorVersion"] != nil { return true }
        if obj["conversation_id"] != nil || obj["conversationId"] != nil { return true }
        return name.first.map { $0.isLowercase } ?? false && ![
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "Notification", "PermissionRequest", "Stop", "StopFailure",
            "SubagentStart", "SubagentStop",
        ].contains(name)
    }

    private static func sourceHint(_ obj: [String: Any]) -> Source? {
        switch string(obj, "source") {
        case "cli": return .cli
        case "claudeApp", "app": return .claudeApp
        case "conductor": return .conductor
        default: return nil
        }
    }

    private static func mappedToolName(_ name: String?) -> String? {
        guard let name else { return nil }
        if name == "Shell" { return "Bash" }
        if name.hasPrefix("MCP:") || name.hasPrefix("mcp:") { return "mcp" }
        return name
    }

    static func toolSummary(name: String?, input: Any?) -> String? {
        guard let input else { return nil }
        let dict = input as? [String: Any]
        let extracted: String?
        switch name {
        case "Read", "Edit", "Write":
            if let path = dict.flatMap({ string($0, "file_path", "filePath", "path") }) {
                extracted = URL(fileURLWithPath: path).lastPathComponent
            } else {
                extracted = nil
            }
        case "Bash", "Shell":
            extracted = dict.flatMap { string($0, "command") }.map { interestingCommand($0) }
        default:
            extracted = nil
        }
        // Commands are often multi-line (heredocs); collapse so a row stays one line.
        return extracted
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .map { String($0.prefix(80)) }
    }

    /// Drop leading `cd <path> &&` hops so the row shows the command that matters. Nearly every
    /// agent command starts by changing directory, which otherwise eats the whole row.
    private static func interestingCommand(_ command: String) -> String {
        var rest = command.trimmingCharacters(in: .whitespacesAndNewlines)
        while rest.hasPrefix("cd ") {
            guard let separator = rest.range(of: "&&") else { break }
            rest = String(rest[separator.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(rest.prefix(40))
    }

    private static func string(_ obj: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = obj[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func bool(_ obj: [String: Any], _ keys: String...) -> Bool? {
        for key in keys {
            if let value = obj[key] as? Bool { return value }
            if let value = obj[key] as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        }
        return nil
    }

    private static func truthy(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        return false
    }
}
