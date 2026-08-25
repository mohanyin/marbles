import Foundation

enum FocusPreviewTests {
    static func run() {
        waitingBeatsTool()
        toolBeatsAssistant()
        assistantBeatsStatus()
        statusFallback()
        toolLines()
        truncatesLongAssistant()
        actionsFollowSource()
    }

    private static func waitingBeatsTool() {
        var agent = Agent.make(id: "w", source: .cli, status: .waitingOnUser)
        agent.currentTool = ToolEvent(id: "t", name: "Edit", fileHint: "Auth.swift", phase: .started, at: Date())
        agent.lastAssistantPreview = "should not show"
        TestRun.expectEqual(FocusPreview.line(for: agent), "Waiting for you")
    }

    private static func toolBeatsAssistant() {
        var agent = Agent.make(id: "t", source: .cli, status: .working, lastAssistantPreview: "nope")
        agent.currentTool = ToolEvent(id: "t", name: "Edit", fileHint: "AuthService.swift", phase: .started, at: Date())
        TestRun.expectEqual(FocusPreview.line(for: agent), "Editing AuthService.swift")
    }

    private static func assistantBeatsStatus() {
        let agent = Agent.make(id: "a", source: .cli, status: .thinking, lastAssistantPreview: "  Looking at the hook mapper.  ")
        TestRun.expectEqual(FocusPreview.line(for: agent), "Looking at the hook mapper.")
    }

    private static func statusFallback() {
        TestRun.expectEqual(FocusPreview.line(for: Agent.make(id: "f", source: .cli, status: .finished)), "Done")
        TestRun.expectEqual(FocusPreview.line(for: Agent.make(id: "e", source: .cli, status: .error)), "Something went wrong")
        TestRun.expectEqual(FocusPreview.line(for: Agent.make(id: "k", source: .cli, status: .working)), "Working…")
    }

    private static func toolLines() {
        let read = ToolEvent(id: "r", name: "Read", fileHint: "Models.swift", phase: .started, at: Date())
        TestRun.expectEqual(FocusPreview.toolLine(read), "Reading Models.swift")
        let bash = ToolEvent(id: "b", name: "Bash", fileHint: nil, phase: .started, at: Date())
        TestRun.expectEqual(FocusPreview.toolLine(bash), "Running a command")
    }

    private static func truncatesLongAssistant() {
        let text = String(repeating: "a", count: 400)
        let agent = Agent.make(id: "long", source: .cli, status: .thinking, lastAssistantPreview: text)
        let line = FocusPreview.line(for: agent)
        TestRun.expect(line.count <= FocusPreview.maxCharacters, "≤280 chars")
        TestRun.expect(line.hasSuffix("…"), "ellipsis")
    }

    private static func actionsFollowSource() {
        let cursor = FocusPreview.actions(for: Agent.make(id: "c", source: .cursor))
        TestRun.expect(!cursor.showClaudeCode && cursor.showCursor, "cursor shows Open Cursor")
        TestRun.expect(cursor.showTerminal && !cursor.showConductor, "cursor hides Conductor")

        let cli = FocusPreview.actions(for: Agent.make(id: "cli", source: .cli))
        TestRun.expect(cli.showClaudeCode && !cli.showCursor, "cli shows Claude Code")

        let conductor = FocusPreview.actions(for: Agent.make(
            id: "cd",
            source: .conductor,
            cwd: URL(fileURLWithPath: "/Users/x/conductor/workspaces/app/ws"),
            conductorWorkspaceID: "ws"
        ))
        TestRun.expect(conductor.showConductor, "conductor cwd shows Open Conductor")
    }
}
