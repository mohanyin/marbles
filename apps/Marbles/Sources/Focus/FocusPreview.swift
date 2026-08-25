import Foundation

enum FocusPreview {
    static let maxCharacters = 280

    static func line(for agent: Agent) -> String {
        if agent.status == .waitingOnUser {
            return "Waiting for you"
        }
        if let tool = agent.currentTool {
            return toolLine(tool)
        }
        if let text = trimmed(agent.lastAssistantPreview), !text.isEmpty {
            return truncate(text)
        }
        return statusWord(agent.status)
    }

    static func toolLine(_ tool: ToolEvent) -> String {
        let file = tool.fileHint.flatMap(trimmed)
        switch tool.name {
        case "Edit", "Write", "NotebookEdit":
            return file.map { "Editing \($0)" } ?? "Editing"
        case "Read":
            return file.map { "Reading \($0)" } ?? "Reading"
        case "Bash", "Shell":
            return file.map { "Running \($0)" } ?? "Running a command"
        case "Grep", "Glob":
            return file.map { "Searching \($0)" } ?? "Searching"
        case "WebSearch", "WebFetch":
            return file.map { "Fetching \($0)" } ?? "Fetching"
        case "Task":
            return file.map { "Delegating \($0)" } ?? "Delegating"
        default:
            if let file {
                return "\(displayName(tool.name)) · \(file)"
            }
            return displayName(tool.name)
        }
    }

    static func statusWord(_ status: AgentStatus) -> String {
        switch status {
        case .working: return "Working…"
        case .thinking: return "Thinking…"
        case .waitingOnUser: return "Waiting for you"
        case .finished: return "Done"
        case .error: return "Something went wrong"
        case .idle: return "Idle"
        }
    }

    static func truncate(_ text: String) -> String {
        if text.count <= maxCharacters { return text }
        return String(text.prefix(maxCharacters - 1)) + "…"
    }

    static func actions(for agent: Agent) -> Actions {
        let cursor = agent.source == .cursor
        return Actions(
            showClaudeCode: !cursor,
            showCursor: cursor,
            showTerminal: true,
            showConductor: agent.conductorWorkspaceID != nil || isConductorCWD(agent.cwd)
        )
    }

    struct Actions: Equatable {
        var showClaudeCode: Bool
        var showCursor: Bool
        var showTerminal: Bool
        var showConductor: Bool
    }

    private static func displayName(_ name: String) -> String {
        if name.hasPrefix("mcp__") {
            return name.split(separator: "_").last.map(String.init) ?? name
        }
        return name
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isConductorCWD(_ cwd: URL?) -> Bool {
        guard let path = cwd?.path else { return false }
        return path.contains("/conductor/workspaces/")
    }
}
