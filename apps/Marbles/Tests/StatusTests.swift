import Foundation

enum StatusTests {
    @MainActor
    static func run() {
        sessionLifecycle()
        finishBlinksThenHolds()
        toolFailureIsNotError()
        stopFailureIsError()
        completionFiresOncePerTurn()
        parseErrorIsIgnored()
        cursorAskIsDropped()
        injectThenClearLeavesLive()
        resumeKeepsSeed()
        rosterCapsAt50()
        emptySessionStartIsHidden()
        titledTranscriptAppearsOnStart()
        abandonedEmptyChatDoesNotLinger()
        toolDwellHoldsChip()
        queuedToolsEachGetDwell()
        stopClearsHeldTool()
        stopPrefersTranscriptReply()
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
        TestRun.expectEqual(store.agents.count, 0, "empty new chat is not a marble")

        store.apply(event("UserPromptSubmit", session: "s1"))
        TestRun.expectEqual(store.agents.count, 1)
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
        TestRun.expectEqual(store.agents[0].status, .working, "chip holds through dwell")
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Edit")
        TestRun.expectEqual(store.agents[0].currentTool?.phase, .succeeded)
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(1))
        TestRun.expectEqual(store.agents[0].status, .thinking)
        TestRun.expect(store.agents[0].currentTool == nil, "tool clears after dwell")
        TestRun.expectEqual(store.agents[0].recentTools.first?.phase, .succeeded)

        store.apply(event("Stop", session: "s1", extra: ["last_assistant_message": "All set."]))
        TestRun.expectEqual(store.agents[0].status, .finished)
        TestRun.expectEqual(store.agents[0].turnOpen, false)
        TestRun.expect(store.agents[0].lastAssistantPreview == nil, "Claude Stop paraphrase is not the reply")
    }

    @MainActor
    private static func toolFailureIsNotError() {
        let store = makeStore()
        store.apply(event("UserPromptSubmit", session: "s2"))
        store.apply(event("PreToolUse", session: "s2", extra: ["tool_name": "Bash"]))
        store.apply(event("PostToolUseFailure", session: "s2"))
        TestRun.expectEqual(store.agents[0].currentTool?.phase, .failed)
        TestRun.expectEqual(store.agents[0].status, .working, "failed tool is a chip, not error")
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(1))
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
    private static func completionFiresOncePerTurn() {
        let store = makeStore()
        var completions = 0
        store.onCompletion = { _ in completions += 1 }
        store.apply(event("UserPromptSubmit", session: "s4"))
        store.apply(event("Stop", session: "s4"))
        TestRun.expectEqual(completions, 1, "stop completes the turn")
        store.apply(event("Notification", session: "s4", extra: ["notification_type": "agent_completed"]))
        TestRun.expectEqual(completions, 1, "a second completion signal for the same turn is silent")
        store.apply(event("UserPromptSubmit", session: "s4"))
        store.apply(event("StopFailure", session: "s4"))
        TestRun.expectEqual(completions, 1, "a failed turn is not a completion")
        store.apply(event("UserPromptSubmit", session: "s4"))
        store.apply(event("Stop", session: "s4"))
        TestRun.expectEqual(completions, 2, "the next turn completes again")
    }

    @MainActor
    private static func parseErrorIsIgnored() {
        let store = makeStore()
        TestRun.expect(HookMapper.event(from: Data(#"{"parseError":true}"#.utf8)) == nil, "mapper drops parseError")
        store.apply(event("UserPromptSubmit", session: "keep"))
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
        store.apply(event("UserPromptSubmit", session: "live-1"))
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
        store.apply(event("UserPromptSubmit", session: "resume-me"))
        let seed = store.agents[0].seed
        store.apply(event("SessionStart", session: "resume-me", extra: ["source": "resume"]))
        TestRun.expectEqual(store.agents[0].seed, seed)
        TestRun.expectEqual(store.agents[0].id, "resume-me")
        TestRun.expectEqual(store.agents[0].status, .idle)
        TestRun.expect(store.agents[0].currentTool == nil, "resume clears tool")
    }

    @MainActor
    private static func rosterCapsAt50() {
        let store = makeStore()
        for index in 0..<51 {
            store.apply(event("UserPromptSubmit", session: "cap-\(index)"))
        }
        TestRun.expectEqual(store.agents.count, 50, "hard cap")
        TestRun.expect(!store.agents.contains { $0.id == "cap-0" }, "oldest insertion evicted")
        TestRun.expect(store.agents.contains { $0.id == "cap-50" }, "newest kept")
    }

    @MainActor
    private static func emptySessionStartIsHidden() {
        let store = makeStore()
        store.apply(event("SessionStart", session: "blank", extra: ["source": "startup"]))
        TestRun.expectEqual(store.agents.count, 0, "no user turn yet")
        store.apply(event("SessionEnd", session: "blank"))
        TestRun.expectEqual(store.agents.count, 0, "abandoned empty chat stays gone")
    }

    @MainActor
    private static func titledTranscriptAppearsOnStart() {
        let store = makeStore()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("marbles-title-\(UUID().uuidString).jsonl")
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello there"}}
        {"type":"custom-title","customTitle":"Glass orb effect with image distortion"}
        """
        try? jsonl.write(to: file, atomically: true, encoding: .utf8)
        store.apply(event("SessionStart", session: "titled", extra: [
            "source": "startup",
            "transcript_path": file.path,
        ]))
        TestRun.expectEqual(store.agents.count, 1, "named session is a marble")
        TestRun.expectEqual(store.agents[0].title, "Glass orb effect with image distortion")
    }

    @MainActor
    private static func abandonedEmptyChatDoesNotLinger() {
        let store = makeStore()
        store.apply(event("SessionStart", session: "ghost"))
        store.apply(event("SessionEnd", session: "ghost"))
        TestRun.expectEqual(store.agents.count, 0)
    }

    @MainActor
    private static func toolDwellHoldsChip() {
        let store = makeStore()
        store.apply(event("UserPromptSubmit", session: "dwell"))
        store.apply(event("PreToolUse", session: "dwell", extra: ["tool_name": "Edit"]))
        store.apply(event("PostToolUse", session: "dwell"))
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Edit")
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(0.4))
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Edit", "still holding before 500ms")
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(0.6))
        TestRun.expect(store.agents[0].currentTool == nil, "released after 500ms")
    }

    @MainActor
    private static func queuedToolsEachGetDwell() {
        let store = makeStore()
        store.apply(event("UserPromptSubmit", session: "burst"))
        store.apply(event("PreToolUse", session: "burst", extra: ["tool_name": "Edit"]))
        store.apply(event("PostToolUse", session: "burst"))
        store.apply(event("PreToolUse", session: "burst", extra: ["tool_name": "Read"]))
        store.apply(event("PostToolUse", session: "burst"))
        store.apply(event("PreToolUse", session: "burst", extra: ["tool_name": "Bash"]))
        store.apply(event("PostToolUse", session: "burst"))
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Edit")
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(0.6))
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Read")
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(1.2))
        TestRun.expectEqual(store.agents[0].currentTool?.name, "Bash")
        store.advanceAnimationTime(0, now: Date().addingTimeInterval(1.8))
        TestRun.expect(store.agents[0].currentTool == nil, "burst drained")
        TestRun.expectEqual(store.agents[0].status, .thinking)
    }

    @MainActor
    private static func stopClearsHeldTool() {
        let store = makeStore()
        store.apply(event("UserPromptSubmit", session: "halt"))
        store.apply(event("PreToolUse", session: "halt", extra: ["tool_name": "Edit"]))
        store.apply(event("PostToolUse", session: "halt"))
        store.apply(event("Stop", session: "halt"))
        TestRun.expect(store.agents[0].currentTool == nil, "stop does not keep a lingering chip")
        TestRun.expectEqual(store.agents[0].status, .finished)
    }

    @MainActor
    private static func stopPrefersTranscriptReply() {
        let store = makeStore()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("marbles-reply-\(UUID().uuidString).jsonl")
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"can I get a progressive blur"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"I'm considering whether NSVisualEffectView supports a"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Not out of the box — NSVisualEffectView applies one uniform blur strength across its whole bounds."}]}}
        """
        try? jsonl.write(to: file, atomically: true, encoding: .utf8)
        store.apply(event("UserPromptSubmit", session: "reply", extra: ["transcript_path": file.path]))
        store.apply(event("Stop", session: "reply", extra: [
            "transcript_path": file.path,
            "last_assistant_message": "try the alpha gradient mask on the cluster halo",
        ]))
        TestRun.expectEqual(
            store.agents[0].lastAssistantPreview,
            "Not out of the box — NSVisualEffectView applies one uniform blur strength across its whole bounds."
        )
    }

    /// Green pulses three times on arrival, then holds. Guards the timing as
    /// well as the settle: a blink that never ends would read as a stuck agent.
    @MainActor
    private static func finishBlinksThenHolds() {
        var agent = Agent.make(id: "blink", source: .demo, status: .finished)
        let t0 = Date()
        agent.finishedAt = t0

        let green: [LightColor] = [.green, .green, .green]
        let off: [LightColor] = [.off, .off, .off]
        let half = Indicators.finishBlinkPeriod / 2

        func at(_ offset: TimeInterval) -> [LightColor] {
            Indicators.lights(for: agent, now: t0.addingTimeInterval(offset), reducedMotion: false)
        }

        // Starts lit, so the row reads as on the instant the agent finishes.
        TestRun.expectEqual(at(0), green, "blink starts lit")
        for pulse in 0..<Indicators.finishBlinks {
            let base = Double(pulse) * Indicators.finishBlinkPeriod
            TestRun.expectEqual(at(base + half * 0.5), green, "pulse \(pulse) on")
            TestRun.expectEqual(at(base + half * 1.5), off, "pulse \(pulse) off")
        }
        let total = Double(Indicators.finishBlinks) * Indicators.finishBlinkPeriod
        TestRun.expectEqual(at(total + 0.01), green, "settles to steady green")
        TestRun.expectEqual(at(total + 60), green, "still steady a minute later")

        // Reduced motion, and agents restored without a timestamp, skip straight
        // to steady rather than blinking or going dark.
        TestRun.expectEqual(
            Indicators.lights(for: agent, now: t0, reducedMotion: true), green, "reduced motion is steady"
        )
        agent.finishedAt = nil
        TestRun.expectEqual(
            Indicators.lights(for: agent, now: t0, reducedMotion: false), green, "no timestamp is steady"
        )
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
