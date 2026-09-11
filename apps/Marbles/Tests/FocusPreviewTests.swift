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
        condensesToAFewWords()
        prettifiesSlugTitles()
        readsConductorWorkspaceTitle()
        cleansBranchNameTitles()
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
        TestRun.expectEqual(TitleSummary.make(from: "hey, could you please add dark mode to the settings page? it should follow the system."), "Add dark mode to the settings")
        TestRun.expectEqual(TitleSummary.make(from: "push"), "Push")
        TestRun.expectEqual(TitleSummary.make(from: "I want you to rename `foo.swift` to bar.swift"), "Rename to bar.swift")
        TestRun.expectEqual(TitleSummary.make(from: "[Image #1] make the titles more appropriate"), "Make the titles more")
        TestRun.expectEqual(TitleSummary.make(from: "https://example.com/some/long/path"), "Https://example.com/some/long/path", "a bare URL falls back to the raw line")
        TestRun.expect(TitleSummary.make(from: "   ") == nil, "blank prompt yields nothing")
    }

    /// A title is a label, not a sentence: a few words, no trailing rationale, nothing dangling.
    private static func condensesToAFewWords() {
        TestRun.expectEqual(
            TitleSummary.make(from: "refactor the whole authentication module so that tokens are refreshed transparently before they expire"),
            "Refactor the whole authentication",
            "rationale after `so that` is dropped"
        )
        TestRun.expectEqual(
            TitleSummary.make(from: "update the marble titles and then push the branch"),
            "Update the marble titles",
            "a follow-on task is dropped"
        )
        TestRun.expectEqual(
            TitleSummary.make(from: "fix the flaky test because CI keeps failing"),
            "Fix the flaky test",
            "a reason clause is dropped"
        )
        TestRun.expectEqual(
            TitleSummary.make(from: "move the ingest server to a background queue"),
            "Move the ingest server",
            "capped at the word limit"
        )
        TestRun.expectEqual(
            TitleSummary.make(from: "rewrite the renderer to"),
            "Rewrite the renderer",
            "a dangling function word is trimmed"
        )
        TestRun.expectEqual(
            TitleSummary.make(from: "so ship it"),
            "Ship it",
            "a clause break needs a verb and object ahead of it to count"
        )
        for prompt in [
            "add dark mode to the settings page so that it follows the system appearance",
            "look into why the overlay flickers when the menu bar auto-hides",
            "push",
        ] {
            let title = TitleSummary.make(from: prompt) ?? ""
            TestRun.expect(title.count <= TitleSummary.maxLength + 1, "clipped to the cap: \(title)")
            TestRun.expect(!title.contains("  "), "no double spaces: \(title)")
            // A trailing prepositional phrase may run past the cap so the object survives.
            TestRun.expect(
                title.split(separator: " ").count <= TitleSummary.maxWords + 2,
                "stays label-length: \(title)"
            )
        }
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

    /// A session re-badged with a task identifier shows prose, but anything that only resembles
    /// a slug is left exactly as it is.
    private static func prettifiesSlugTitles() {
        TestRun.expectEqual(
            TitleSummary.prettifySlug("cleanup-stale-drafts-scheduled"),
            "Cleanup stale drafts scheduled",
            "a dashed task name reads as prose"
        )
        TestRun.expectEqual(
            TitleSummary.prettifySlug("test_real_content_jsonld"),
            "Test real content jsonld",
            "underscores separate too"
        )
        TestRun.expectEqual(
            TitleSummary.prettifySlug("web-407-customer-story-date"),
            "WEB-407 customer story date",
            "a tracker prefix keeps its issue-key shape"
        )
        for untouched in [
            "install.sh",
            "release-2.1.265",
            "my-script.sh",
            "Marble titles brevity",
            "WEB-285",
            "Mikaela/asana-1213582599582137-blog-highlighting-social-share Easter egg",
            "Asana sync",
            "v2.1.265",
            "--fix",
            "",
        ] {
            TestRun.expectEqual(
                TitleSummary.prettifySlug(untouched),
                untouched,
                "left verbatim: \(untouched)"
            )
        }
    }

    /// Conductor names its own sessions; Marbles reads that name rather than inventing one.
    private static func readsConductorWorkspaceTitle() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marbles-conductor-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("conductor.db")
        let workspace = "/Users/someone/conductor/workspaces/site/yangon"
        let sql = """
        CREATE TABLE workspaces (id TEXT, active_session_id TEXT, workspace_path TEXT);
        CREATE TABLE sessions (id TEXT, title TEXT);
        INSERT INTO workspaces VALUES ('w1','s1','\(workspace)');
        INSERT INTO sessions VALUES ('s1','Daily Brief');
        INSERT INTO workspaces VALUES ('w2','s2','/Users/someone/conductor/workspaces/site/lima');
        INSERT INTO sessions VALUES ('s2','Untitled');
        INSERT INTO workspaces VALUES ('w3','s3','/Users/someone/Repositories/site');
        INSERT INTO sessions VALUES ('s3','Should Never Show');
        """
        guard TestSupport.runSQLite(database: db, sql: sql) else {
            TestRun.expect(false, "could not build the fixture database")
            return
        }
        TestRun.expectEqual(
            ConductorWorkspace.title(forCWD: workspace, database: db),
            "Daily Brief",
            "the workspace's session title is used"
        )
        TestRun.expect(
            ConductorWorkspace.title(
                forCWD: "/Users/someone/conductor/workspaces/site/lima",
                database: db
            ) == nil,
            "Conductor's Untitled placeholder counts as no title"
        )
        TestRun.expect(
            ConductorWorkspace.title(forCWD: "/Users/someone/Repositories/site", database: db) == nil,
            "a non-Conductor cwd is never looked up, even with a row that would match"
        )
        TestRun.expect(
            ConductorWorkspace.title(
                forCWD: "/Users/someone/conductor/workspaces/site/unknown",
                database: db
            ) == nil,
            "an unknown workspace has no title"
        )
    }

    /// A title that is really a branch name loses the owner prefix and tracker id, keeping the
    /// part that says what the work is — but numbers that carry meaning stay put.
    private static func cleansBranchNameTitles() {
        TestRun.expectEqual(
            TitleSummary.deBranch("Mikaela/asana-1213582599582137-blog-highlighting-social-share Easter egg"),
            "Blog highlighting social share Easter egg",
            "owner prefix and asana id are dropped"
        )
        TestRun.expectEqual(
            TitleSummary.deBranch("mikaela/fix-faq-title"),
            "Fix faq title",
            "a plain owner-prefixed branch is cleaned"
        )
        TestRun.expectEqual(
            TitleSummary.deBranch("1213582599582137-blog-highlighting"),
            "Blog highlighting",
            "a leading bare id is dropped"
        )
        for untouched in [
            "PR #2341 blog and customer stories dates",
            "website pull request 2333",
            "Website pull request 2333 merge conflicts",
            "Marble titles brevity",
            "install.sh",
            "Create linear ticket in WEB",
            "a/b/c-deep-path",
        ] {
            TestRun.expectEqual(
                TitleSummary.deBranch(untouched),
                untouched,
                "left verbatim: \(untouched)"
            )
        }
    }
}
