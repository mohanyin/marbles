import Foundation

enum StatusTests {
    @MainActor
    static func run() {
        sessionLifecycle()
        toolFailureIsNotError()
        stopFailureIsError()
        parseErrorIsIgnored()
        cursorAskIsDropped()
        injectThenClearLeavesLive()
        resumeKeepsSeed()
    }

    @MainActor
    private static func makeStore() -> AgentStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marbles-tests-\(UUID().uuidString)")
            .appendingPathComponent("seeds.json")
        return AgentStore(seeds: SeedStore(url: url))
    }

    @MainActor
    private static func sessionLifecycle() {
        let store = makeStore()
        store.apply(event("SessionStart", session: "s1", extra: ["source": "startup"]))
        TestRun.expectEqual(store.agents.count, 1)
        TestRun.expectEqual(store.agents[0].status, .idle)
        TestRun.expectEqual(store.agents[0].latticeIndex, 0)

        store.apply(event("UserPromptSubmit", session: "s1"))
        TestRun.expectEqual(store.agents[0].status, .thinking)
        TestRun.expect(store.agents[0].turnOpen, "turn opens on prompt")

        store.apply(event("PreToolUse", session: "s1", extra: [
            "tool_name": "Edit",
            "tool_input": ["file_path": "/tmp/AuthService.swift"],
        ]))
        TestRun.expectEqual(store.agents[0].status, .working)
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Edit")
        TestRun.expectEqual(store.agents[0].currentTool?.fileHint, "AuthService.swift")

        store.apply(event("PostToolUse", session: "s1"))
        TestRun.expectEqual(store.agents[0].status, .thinking)
        TestRun.expect(store.agents[0].currentTool == nil, "tool cleared after post")
        TestRun.expectEqual(store.agents[0].recentTools.first?.phase, .succeeded)

        store.apply(event("Stop", session: "s1", extra: ["last_assistant_message": "All set."]))
        TestRun.expectEqual(store.agents[0].status, .finished)
        TestRun.expectEqual(store.agents[0].turnOpen, false)
        TestRun.expectEqual(store.agents[0].lastAssistantPreview, "All set.")
    }

    @MainActor
    private static func toolFailureIsNotError() {
        let store = makeStore()
        store.apply(event("UserPromptSubmit", session: "s2"))
        store.apply(event("PreToolUse", session: "s2", extra: ["tool_name": "Bash"]))
        store.apply(event("PostToolUseFailure", session: "s2"))
        TestRun.expectEqual(store.agents[0].status, .thinking, "failed tool is a chip, not error")
        TestRun.expectEqual(store.agents[0].recentTools.first?.phase, .failed)
    }

    @MainActor
    private static func stopFailureIsError() {
        let store = makeStore()
        store.apply(event("UserPromptSubmit", session: "s3"))
        store.apply(event("StopFailure", session: "s3"))
        TestRun.expectEqual(store.agents[0].status, .error)
        TestRun.expectEqual(store.agents[0].turnOpen, false)
    }

    @MainActor
    private static func parseErrorIsIgnored() {
        let store = makeStore()
        TestRun.expect(HookMapper.event(from: Data(#"{"parseError":true}"#.utf8)) == nil, "mapper drops parseError")
        store.apply(event("SessionStart", session: "keep"))
        let count = store.agents.count
        if let parsed = HookMapper.event(from: Data(#"{"parseError":true}"#.utf8)) {
            store.apply(parsed)
        }
        TestRun.expectEqual(store.agents.count, count)
    }

    @MainActor
    private static func cursorAskIsDropped() {
        let data = Data(#"{"hook_event_name":"sessionStart","conversation_id":"ask-1","composer_mode":"ask","cursor_version":"1"}"#.utf8)
        TestRun.expect(HookMapper.event(from: data) == nil, "ask composer is not a marble")
        let agent = Data(#"{"hook_event_name":"sessionStart","conversation_id":"ag-1","composer_mode":"agent","cursor_version":"1"}"#.utf8)
        TestRun.expectEqual(HookMapper.event(from: agent)?.sessionID, "ag-1")
        TestRun.expectEqual(HookMapper.event(from: agent)?.sourceHint, .cursor)
    }

    @MainActor
    private static func injectThenClearLeavesLive() {
        let store = makeStore()
        store.apply(event("SessionStart", session: "live-1"))
        store.injectDebugAgents(count: 3)
        TestRun.expect(store.agents.contains { $0.id == "live-1" }, "live session stays")
        TestRun.expect(store.agents.contains { $0.id.hasPrefix("debug-") }, "dummies present")
        TestRun.expectEqual(store.agent(id: "debug-0")?.status, .working)
        TestRun.expectEqual(store.agent(id: "debug-1")?.status, .thinking)
        TestRun.expectEqual(store.agent(id: "debug-2")?.status, .finished)
        store.clearInjected()
        TestRun.expectEqual(store.agents.map(\.id), ["live-1"])
    }

    @MainActor
    private static func resumeKeepsSeed() {
        let store = makeStore()
        store.apply(event("SessionStart", session: "resume-me", extra: ["source": "startup"]))
        let seed = store.agents[0].seed
        let slot = store.agents[0].latticeIndex
        store.apply(event("UserPromptSubmit", session: "resume-me"))
        store.apply(event("SessionStart", session: "resume-me", extra: ["source": "resume"]))
        TestRun.expectEqual(store.agents[0].seed, seed)
        TestRun.expectEqual(store.agents[0].latticeIndex, slot)
        TestRun.expectEqual(store.agents[0].status, .idle)
        TestRun.expect(store.agents[0].currentTool == nil, "resume clears tool")
    }

    private static func event(_ name: String, session: String, extra: [String: Any] = [:]) -> HookEvent {
        var payload: [String: Any] = [
            "hook_event_name": name,
            "session_id": session,
        ]
        extra.forEach { payload[$0.key] = $0.value }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return HookMapper.event(from: data)!
    }
}
