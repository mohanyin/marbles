import Foundation

enum MotionTests {
    static func run() {
        timeAdvancesOnlyWhileWorkingOrThinking()
        waitingHoldsTimeAndIsNotFrozen()
        errorSkipsBloom()
        finishedBloomsThenSettles()
        freezeKeepsAnimationTime()
        clusterChipPriority()
    }

    private static func timeAdvancesOnlyWhileWorkingOrThinking() {
        TestRun.expect(MotionEngine.shouldAdvanceTime(.working), "working advances")
        TestRun.expect(MotionEngine.shouldAdvanceTime(.thinking), "thinking advances")
        TestRun.expect(!MotionEngine.shouldAdvanceTime(.waitingOnUser), "waiting holds")
        TestRun.expect(!MotionEngine.shouldAdvanceTime(.finished), "finished holds")
        TestRun.expect(!MotionEngine.shouldAdvanceTime(.error), "error holds")
        TestRun.expect(!MotionEngine.shouldAdvanceTime(.idle), "idle holds")
    }

    private static func waitingHoldsTimeAndIsNotFrozen() {
        var agent = Agent.debugDummy(index: 0)
        agent.status = .waitingOnUser
        agent.animationTime = 3.5
        let uniforms = MotionEngine.uniforms(for: agent, now: Date(), reducedMotion: false, dim: 0)
        TestRun.expectEqual(uniforms.time, 3.5, "waiting holds time")
        TestRun.expectEqual(uniforms.hold, 1)
        TestRun.expectEqual(uniforms.freeze, 0, "waiting is hold, not freeze")
        TestRun.expectEqual(uniforms.advection, 0)
        TestRun.expect(uniforms.attention > 0, "waiting pulses")
    }

    private static func errorSkipsBloom() {
        var agent = Agent.debugDummy(index: 1)
        agent.status = .error
        agent.errorHueStartedAt = Date().addingTimeInterval(-1)
        agent.bloomStartedAt = nil
        let uniforms = MotionEngine.uniforms(for: agent, now: Date(), reducedMotion: false, dim: 0)
        TestRun.expectEqual(uniforms.freeze, 1)
        TestRun.expect(uniforms.errorHue > 0.9, "error hue on")
        TestRun.expectEqual(uniforms.bloom, 0, "error skips bloom")
        TestRun.expectEqual(Chips.clusterChip(for: agent), nil, "error uses hue, no chip")
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
        TestRun.expectEqual(Chips.clusterChip(for: agent), .finished)
    }

    private static func freezeKeepsAnimationTime() {
        var agent = Agent.debugDummy(index: 3)
        agent.status = .finished
        agent.animationTime = 8
        let uniforms = MotionEngine.uniforms(for: agent, now: Date(), reducedMotion: false, dim: 0)
        TestRun.expectEqual(uniforms.time, 8)
        TestRun.expectEqual(uniforms.freeze, 1)
        TestRun.expectEqual(uniforms.advection, 0)
    }

    private static func clusterChipPriority() {
        var agent = Agent.debugDummy(index: 4)
        agent.status = .thinking
        TestRun.expectEqual(Chips.clusterChip(for: agent), .thinking)
        agent.currentTool = ToolEvent(id: "1", name: "Edit", fileHint: "A.swift", phase: .started, at: Date())
        TestRun.expectEqual(Chips.clusterChip(for: agent), .tool("Edit"))
        agent.currentTool?.phase = .failed
        TestRun.expectEqual(Chips.clusterChip(for: agent), .toolFail)
    }
}
