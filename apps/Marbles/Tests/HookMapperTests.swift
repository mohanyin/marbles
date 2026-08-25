import Foundation

enum HookMapperTests {
    static func run() {
        decodeRepoFixtures()
        toolSummaryRules()
        missingSessionDrops()
        cursorStopError()
    }

    private static func decodeRepoFixtures() {
        let fixtures = fixtureDirectory()
        TestRun.expect(fixtures != nil, "fixture directory exists")
        guard let fixtures else { return }

        let start = load(fixtures, "session-start.json")
        TestRun.expectEqual(start?.kind, .sessionStart)
        TestRun.expectEqual(start?.sessionID, "review-session")

        let prompt = load(fixtures, "user-prompt.json")
        TestRun.expectEqual(prompt?.kind, .userPromptSubmit)

        let tool = load(fixtures, "pre-tool-use.json")
        TestRun.expectEqual(tool?.kind, .preToolUse)
        TestRun.expectEqual(tool?.toolName, "Edit")
        TestRun.expectEqual(tool?.toolInputSummary, "AgentStore.swift")

        TestRun.expectEqual(load(fixtures, "stop.json")?.kind, .stop)
        TestRun.expectEqual(load(fixtures, "stop-failure.json")?.kind, .stopFailure)
        TestRun.expectEqual(load(fixtures, "cursor-session-start.json")?.sourceHint, .cursor)
        TestRun.expect(HookMapper.event(from: data(fixtures, "parse-error.json") ?? Data()) == nil, "parseError fixture")
    }

    private static func toolSummaryRules() {
        TestRun.expectEqual(
            HookMapper.toolSummary(name: "Read", input: ["file_path": "/a/b/c.rs"]),
            "c.rs"
        )
        TestRun.expectEqual(
            HookMapper.toolSummary(name: "Bash", input: ["command": String(repeating: "x", count: 80)]),
            String(repeating: "x", count: 40)
        )
        TestRun.expect(HookMapper.toolSummary(name: "Grep", input: ["pattern": "foo"]) == nil, "unknown tools omit summary")
    }

    private static func missingSessionDrops() {
        let data = Data(#"{"hook_event_name":"Stop"}"#.utf8)
        TestRun.expect(HookMapper.event(from: data) == nil, "no session_id")
    }

    private static func cursorStopError() {
        let data = Data(#"{"hook_event_name":"stop","conversation_id":"c1","status":"error","cursor_version":"1"}"#.utf8)
        let event = HookMapper.event(from: data)
        TestRun.expectEqual(event?.kind, .stop)
        TestRun.expectEqual(event?.stopStatus, "error")
    }

    private static func fixtureDirectory() -> URL? {
        FixtureFiles.hooksDirectory(startingAt: #filePath)
    }

    private static func load(_ directory: URL, _ name: String) -> HookEvent? {
        guard let data = data(directory, name) else { return nil }
        return HookMapper.event(from: data)
    }

    private static func data(_ directory: URL, _ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }
}
