import Foundation

struct MarbleFrameUniforms: Equatable {
    var time: Float
    var advection: Float
    var pulse: Float
    var freeze: Float
    var hold: Float
    var errorHue: Float
    var bloom: Float
    var attention: Float
    var dim: Float
    var rimBoost: Float
}

enum MotionEngine {
    static let bloomDuration: TimeInterval = 0.55
    static let errorEase: TimeInterval = 0.25
    static let maxConcurrentBlooms = 4

    static func shouldAdvanceTime(_ status: AgentStatus) -> Bool {
        status == .working || status == .thinking
    }

    static func bloomEnvelope(startedAt: Date?, now: Date) -> Float {
        guard let startedAt else { return 0 }
        let t = now.timeIntervalSince(startedAt)
        if t < 0 { return 0 }
        if t >= bloomDuration { return 0 }
        let u = Float(t / bloomDuration)
        return 4 * u * (1 - u)
    }

    static func errorHue(agent: Agent, now: Date) -> Float {
        if agent.status == .error {
            guard let started = agent.errorHueStartedAt else { return 1 }
            return Float(min(1, now.timeIntervalSince(started) / errorEase))
        }
        if let released = agent.errorHueReleasedAt {
            return Float(max(0, 1 - now.timeIntervalSince(released) / errorEase))
        }
        return 0
    }

    static func uniforms(for agent: Agent, now: Date, reducedMotion: Bool, dim: CGFloat) -> MarbleFrameUniforms {
        let waiting = agent.status == .waitingOnUser
        let frozen = agent.status == .finished || agent.status == .error
        let working = agent.status == .working
        let thinking = agent.status == .thinking
        let bloom = bloomEnvelope(startedAt: agent.bloomStartedAt, now: now)
        let settledFinished = agent.status == .finished && bloom == 0
        let advection: Float
        if reducedMotion {
            advection = 0
        } else if working {
            advection = 1
        } else if thinking {
            advection = 0.35
        } else {
            advection = 0
        }
        let attention: Float
        if waiting, !reducedMotion {
            attention = 0.45 + 0.55 * (0.5 + 0.5 * sin(Float(now.timeIntervalSinceReferenceDate) * 3))
        } else {
            attention = 0
        }
        return MarbleFrameUniforms(
            time: agent.animationTime,
            advection: advection,
            pulse: thinking && !reducedMotion ? 1 : 0,
            freeze: frozen ? 1 : 0,
            hold: waiting ? 1 : 0,
            errorHue: errorHue(agent: agent, now: now),
            bloom: bloom,
            attention: attention,
            dim: Float(dim),
            rimBoost: settledFinished ? 0.15 : 0
        )
    }
}
