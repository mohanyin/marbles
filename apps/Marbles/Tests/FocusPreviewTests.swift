import Foundation

enum FocusPreviewTests {
    static func run() {
        waitingBeatsTool()
        toolBeatsAssistant()
        assistantBeatsStatus()
        statusFallback()
        toolLines()
        truncatesLongAssistant()
        showsSessionTitle()
        latestAssistantSkipsThinking()
        latestUserTakesMostRecent()
        promptReadsLastUserTurn()
        expandsTildeInTranscriptPath()
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
        let text = String(repeating: "a", count: IngestConstants.previewLimit + 50)
        let agent = Agent.make(id: "long", source: .cli, status: .thinking, lastAssistantPreview: text)
        let line = FocusPreview.line(for: agent)
        TestRun.expect(line.count <= FocusPreview.maxCharacters, "capped")
        TestRun.expect(line.hasSuffix("…"), "ellipsis")
    }

    private static func latestUserTakesMostRecent() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"first ask"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sure"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"second ask"}}"#,
        ].joined(separator: "\n")
        let text = TranscriptPeek.latestUserText(data: Data(lines.utf8))
        TestRun.expectEqual(text, "second ask", "latest user turn wins, tool results skipped")

        let sidechain = #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent"}}"#
        let withSide = lines + "\n" + sidechain
        TestRun.expectEqual(
            TranscriptPeek.latestUserText(data: Data(withSide.utf8)),
            "second ask",
            "sidechain user turns are skipped"
        )
    }

    private static func promptReadsLastUserTurn() {
        var agent = Agent.make(id: "p", source: .cli, status: .working)
        TestRun.expect(FocusPreview.prompt(for: agent) == nil, "no prompt when unset")

        agent.lastUserPrompt = "   "
        TestRun.expect(FocusPreview.prompt(for: agent) == nil, "blank prompt collapses to nil")

        agent.lastUserPrompt = "  fix the layout  "
        TestRun.expectEqual(FocusPreview.prompt(for: agent), "fix the layout", "prompt is trimmed")

        agent.lastUserPrompt = String(repeating: "x", count: FocusPreview.maxCharacters + 50)
        let capped = FocusPreview.prompt(for: agent) ?? ""
        TestRun.expectEqual(capped.count, FocusPreview.maxCharacters, "prompt truncates at the cap")
        TestRun.expect(capped.hasSuffix("…"), "truncated prompt ends with an ellipsis")
    }

    private static func showsSessionTitle() {
        var agent = Agent.make(id: "titled", source: .cli, status: .working, title: "Glass orb effect with image distortion")
        TestRun.expectEqual(FocusPreview.title(for: agent), "Glass orb effect with image distortion")
        TestRun.expectEqual(FocusPreview.line(for: agent), "Working…")
        agent.title = "  "
        TestRun.expect(FocusPreview.title(for: agent) == nil, "blank title hides")
    }

    private static func latestAssistantSkipsThinking() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"I'm considering whether NSVisualEffectView supports a"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Not out of the box — NSVisualEffectView applies one uniform blur strength across its whole bounds."}]}}
        """
        let text = TranscriptPeek.latestAssistantText(data: Data(jsonl.utf8))
        TestRun.expectEqual(text, "Not out of the box — NSVisualEffectView applies one uniform blur strength across its whole bounds.")
        TestRun.expect(!(text ?? "").contains("I'm considering"), "thinking is not the preview")
    }

    private static func expandsTildeInTranscriptPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = TranscriptPeek.resolvedPath(
            sessionID: "no-such-session",
            cwd: nil,
            explicit: "~/.claude/projects/fake/no-such-session.jsonl"
        )
        TestRun.expectEqual(path, "\(home)/.claude/projects/fake/no-such-session.jsonl")
    }
}
