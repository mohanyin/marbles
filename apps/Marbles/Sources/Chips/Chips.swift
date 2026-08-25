import Foundation

enum ChipKind: Equatable {
    case thinking
    case tool(String)
    case permission
    case finished
    case toolFail

    var symbolName: String {
        switch self {
        case .thinking:
            return "ellipsis"
        case .permission:
            return "questionmark"
        case .finished:
            return "checkmark"
        case .toolFail:
            return "exclamationmark"
        case .tool(let name):
            return Chips.symbol(forTool: name)
        }
    }
}

enum Chips {
    static func symbol(forTool name: String) -> String {
        switch name {
        case "Read":
            return "doc.text"
        case "Write", "Edit", "NotebookEdit":
            return "pencil"
        case "Bash", "Shell":
            return "apple.terminal"
        case "Grep", "Glob":
            return "magnifyingglass"
        case "WebSearch", "WebFetch":
            return "globe"
        case "Task":
            return "arrow.triangle.branch"
        case "mcp":
            return "powerplug"
        default:
            if name.hasPrefix("mcp__") || name.hasPrefix("MCP") { return "powerplug" }
            return "circle.hexagonpath"
        }
    }

    static func clusterChip(for agent: Agent) -> ChipKind? {
        if let tool = agent.currentTool {
            return tool.phase == .failed ? .toolFail : .tool(tool.name)
        }
        if agent.recentTools.first?.phase == .failed, agent.status == .thinking {
            return .toolFail
        }
        switch agent.status {
        case .thinking:
            return .thinking
        case .waitingOnUser:
            return .permission
        case .finished:
            return .finished
        case .working, .idle, .error:
            return nil
        }
    }

    static func activeChips(for agent: Agent, now: Date) -> [(ChipKind, CGFloat)] {
        var items: [(ChipKind, CGFloat)] = []
        if let live = clusterChip(for: agent) {
            items.append((live, 1))
        }
        for tool in agent.recentTools.prefix(2) {
            let age = now.timeIntervalSince(tool.at)
            let alpha = CGFloat(max(0, min(1, 1 - age / 2)))
            if alpha > 0.05 {
                items.append((tool.phase == .failed ? .toolFail : .tool(tool.name), alpha))
            }
        }
        return items
    }

    static func size(for marbleSize: CGFloat) -> CGFloat {
        if marbleSize <= 40 { return 18 }
        if marbleSize <= 64 { return 22 }
        return 24
    }

    static func center(for marble: MarbleFrame, index: Int = 0) -> CGPoint {
        let angle = -.pi / 4 - CGFloat(index) * 0.7
        let radius = marble.size / 2
        return CGPoint(
            x: marble.center.x + cos(angle) * radius,
            y: marble.center.y + sin(angle) * radius
        )
    }
}
