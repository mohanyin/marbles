import Foundation

enum MotionTests {
    @MainActor
    static func run() {
        timeScaleByStatus()
        reducedMotionFreezes()
        storeAdvancesAtStatusSpeed()
        reducedMotionHoldsStoreTime()
        errorSkipsBloom()
        finishedBloomsThenSettles()
        neverResetsAnimationTime()
        indicatorPatterns()
        toolFlashUsesOneOrTwoLights()
    }

    private static func timeScaleByStatus() {
        TestRun.expectEqual(MotionEngine.timeScale(for: .working), 1.5)
        TestRun.expectEqual(MotionEngine.timeScale(for: .thinking), 1.5)
        TestRun.expectEqual(MotionEngine.timeScale(for: .waitingOnUser), 0.25)
        TestRun.expectEqual(MotionEngine.timeScale(for: .idle), 0.05)
        TestRun.expectEqual(MotionEngine.timeScale(for: .finished), 0.05)
        TestRun.expectEqual(MotionEngine.timeScale(for: .error), 0.05)
    }

    private static func reducedMotionFreezes() {
        for status in [AgentStatus.working, .thinking, .waitingOnUser, .idle, .finished, .error] {
            TestRun.expectEqual(MotionEngine.timeScale(for: status, reducedMotion: true), 0, "\(status) freezes")
        }
    }

    @MainActor
    private static func storeAdvancesAtStatusSpeed() {
        let store = makeStore()
        store.injectDebugAgents(count: 3)
        store.setStatus(.working, for: store.agents[0].id)
        store.setStatus(.waitingOnUser, for: store.agents[1].id)
        store.setStatus(.finished, for: store.agents[2].id)
        store.advanceAnimationTime(2)
        TestRun.expectEqual(store.agents[0].animationTime, 3, "working 1.5×")
        TestRun.expectEqual(store.agents[1].animationTime, 0.5, "waiting 0.25×")
        TestRun.expectEqual(store.agents[2].animationTime, 0.1, "finished 0.05×")
    }

    @MainActor
    private static func reducedMotionHoldsStoreTime() {
        let store = makeStore()
        store.injectDebugAgents(count: 1)
        store.setStatus(.working, for: store.agents[0].id)
        store.advanceAnimationTime(1, reducedMotion: true)
        TestRun.expectEqual(store.agents[0].animationTime, 0, "reduced motion freezes")
    }

    private static func errorSkipsBloom() {
        var agent = Agent.debugDummy(index: 1)
        agent.status = .error
        agent.errorHueStartedAt = Date().addingTimeInterval(-1)
        agent.bloomStartedAt = nil
        let uniforms = MotionEngine.uniforms(for: agent, now: Date(), reducedMotion: false, dim: 0)
        TestRun.expect(uniforms.errorHue > 0.9, "error hue on")
        TestRun.expectEqual(uniforms.bloom, 0, "error skips bloom")
        TestRun.expectEqual(Indicators.lights(for: agent, now: Date(), reducedMotion: true), [.red, .red, .red], "error is all red")
    }

    private static func finishedBloomsThenSettles() {
        var agent = Agent.debugDummy(index: 2)
        agent.status = .finished
        agent.bloomStartedAt = Date()
        let blooming = MotionEngine.uniforms(for: agent, now: Date().addingTimeInterval(0.2), reducedMotion: false, dim: 0)
        TestRun.expect(blooming.bloom > 0, "bloom in progress")
        TestRun.expectEqual(blooming.rimBoost, 0)

        agent.bloomStartedAt = Date().addingTimeInterval(-1)
        let settled = MotionEngine.uniforms(for: agent, now: Date(), reducedMotion: false, dim: 0)
        TestRun.expectEqual(settled.bloom, 0)
        TestRun.expect(settled.rimBoost > 0, "settled finished keeps rim")
        TestRun.expectEqual(Indicators.lights(for: agent, now: Date(), reducedMotion: true), [.green, .green, .green], "finished is all green")
    }

    private static func neverResetsAnimationTime() {
        var agent = Agent.debugDummy(index: 3)
        agent.status = .finished
        agent.animationTime = 8
        let uniforms = MotionEngine.uniforms(for: agent, now: Date(), reducedMotion: false, dim: 0)
        TestRun.expectEqual(uniforms.time, 8)
    }

    private static func indicatorPatterns() {
        var agent = Agent.debugDummy(index: 4)
        agent.status = .idle
        TestRun.expectEqual(Indicators.lights(for: agent, now: Date(), reducedMotion: false), [.off, .off, .off], "idle off")
        agent.status = .waitingOnUser
        TestRun.expectEqual(Indicators.lights(for: agent, now: Date(), reducedMotion: false), [.white, .white, .white], "waiting white")
        agent.status = .finished
        TestRun.expectEqual(Indicators.lights(for: agent, now: Date(), reducedMotion: false), [.green, .green, .green], "finished green")
        agent.status = .error
        TestRun.expectEqual(Indicators.lights(for: agent, now: Date(), reducedMotion: false), [.red, .red, .red], "error red")
        agent.status = .thinking
        let wave = Indicators.lights(for: agent, now: Date(timeIntervalSinceReferenceDate: 0), reducedMotion: false)
        TestRun.expectEqual(wave.filter { $0 == .white }.count, 1, "thinking wave one light")
        TestRun.expectEqual(wave[0], .white, "wave starts at first light")
        let held = Indicators.lights(for: agent, now: Date(timeIntervalSinceReferenceDate: 10), reducedMotion: true)
        TestRun.expectEqual(held, [.white, .off, .off], "reduced motion holds first")
    }

    private static func toolFlashUsesOneOrTwoLights() {
        var agent = Agent.debugDummy(index: 5)
        agent.status = .working
        agent.currentTool = ToolEvent(id: "edit-1", name: "Edit", fileHint: "A.swift", phase: .started, at: Date())
        let mask = Indicators.flashMask(seed: agent.seed, toolID: "edit-1")
        let count = mask.filter { $0 }.count
        TestRun.expect(count == 1 || count == 2, "flash 1 or 2, got \(count)")
        TestRun.expect(count < 3, "never all three")
        let frozen = Indicators.lights(for: agent, now: Date(), reducedMotion: true)
        TestRun.expectEqual(frozen.filter { $0 == .white }.count, count, "reduced motion holds subset")
        agent.currentTool?.phase = .failed
        let failed = Indicators.lights(for: agent, now: Date(), reducedMotion: true)
        TestRun.expect(!failed.contains(.red), "failed tool is not red")
        TestRun.expectEqual(failed.filter { $0 == .white }.count, count, "failed tool stays white flash")
    }

    @MainActor
    private static func makeStore() -> AgentStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marbles-motion-\(UUID().uuidString)")
            .appendingPathComponent("seeds.json")
        return AgentStore(seeds: SeedStore(url: url))
    }
}
