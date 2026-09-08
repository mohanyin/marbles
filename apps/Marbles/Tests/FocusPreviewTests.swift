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
        aiTitleBeatsFirstPrompt()
        customTitleBeatsAITitle()
        aiTitlePastHeadLimitIsFound()
        summarizesFirstPrompt()
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

    private static func aiTitleBeatsFirstPrompt() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"can you fix merge conflicts: https://github.com/x/y/pull/1"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."}]}}
        {"type":"ai-title","aiTitle":"Resolve PR merge conflicts"}
        {"type":"user","message":{"role":"user","content":"push"}}
        {"type":"ai-title","aiTitle":"Resolve and push PR merge conflicts"}
        """
        let snap = TranscriptPeek.inspect(data: Data(jsonl.utf8))
        TestRun.expectEqual(snap.title, "Resolve and push PR merge conflicts", "newest generated title wins over the prompt")
        TestRun.expectEqual(snap.titleSource, .ai)

        let early = TranscriptPeek.inspect(data: Data(jsonl.split(separator: "\n").prefix(2).joined(separator: "\n").utf8))
        TestRun.expectEqual(early.title, "Fix merge conflicts", "before a generated title exists the prompt is summarized")
        TestRun.expectEqual(early.titleSource, .prompt)
    }

    private static func customTitleBeatsAITitle() {
        let jsonl = """
        {"type":"custom-title","customTitle":"Asana sync"}
        {"type":"user","message":{"role":"user","content":"sync the tasks"}}
        {"type":"ai-title","aiTitle":"Sync Asana tasks to Linear"}
        {"type":"agent-name","agentName":"helper"}
        """
        let snap = TranscriptPeek.inspect(data: Data(jsonl.utf8))
        TestRun.expectEqual(snap.title, "Asana sync", "a /rename beats everything")
        TestRun.expectEqual(snap.titleSource, .custom)
    }

    private static func aiTitlePastHeadLimitIsFound() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("marbles-aititle-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let filler = String(repeating: "x", count: 4000)
        var lines = [#"{"type":"user","message":{"role":"user","content":"could you please look at the flaky test"}}"#]
        for _ in 0..<60 {
            lines.append(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(filler)"}]}}"#)
        }
        lines.append(#"{"type":"ai-title","aiTitle":"Stabilize flaky integration test"}"#)
        lines.append(#"{"type":"user","message":{"role":"user","content":"thanks, now push it"}}"#)
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        let snap = TranscriptPeek.inspect(path: file.path)
        TestRun.expectEqual(snap.title, "Stabilize flaky integration test", "generated title beyond the head scan is picked up from the tail")
        TestRun.expect(snap.hasConversation, "conversation detected")
    }

    private static func summarizesFirstPrompt() {
        TestRun.expectEqual(TitleSummary.make(from: "can you fix merge conflicts: https://github.com/harvey/website/pull/2333"), "Fix merge conflicts")
        TestRun.expectEqual(TitleSummary.make(from: "hey, could you please add dark mode to the settings page? it should follow the system."), "Add dark mode to the settings page")
        TestRun.expectEqual(TitleSummary.make(from: "push"), "Push")
        TestRun.expectEqual(TitleSummary.make(from: "I want you to rename `foo.swift` to bar.swift"), "Rename to bar.swift")
        TestRun.expectEqual(TitleSummary.make(from: "[Image #1] make the titles more appropriate"), "Make the titles more appropriate")
        TestRun.expectEqual(TitleSummary.make(from: "https://example.com/some/long/path"), "Https://example.com/some/long/path", "a bare URL falls back to the raw line")
        let long = TitleSummary.make(from: "refactor the whole authentication module so that tokens are refreshed transparently before they expire and users never see a login screen") ?? ""
        TestRun.expect(long.count <= TitleSummary.maxLength + 1, "clipped to the cap")
        TestRun.expect(long.hasSuffix("…"), "clip marks the cut")
        TestRun.expect(!long.contains("  "), "no double spaces")
        TestRun.expect(TitleSummary.make(from: "   ") == nil, "blank prompt yields nothing")
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
