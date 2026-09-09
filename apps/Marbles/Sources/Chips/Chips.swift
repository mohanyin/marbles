import Foundation
import AppKit

enum LightColor: Equatable {
    case off
    case white
    case green
    case red
}

enum Indicators {
    /// Across the row. Uniform, and the only dimension the dock layout reserves.
    static let lightThickness: CGFloat = 4
    /// Along the row. The middle light stays square; the outer two are longer,
    /// which gives the row a direction instead of reading as three dots.
    static let lightLength: CGFloat = 4
    static let endLightLength: CGFloat = 6
    static let lightGap: CGFloat = 2
    static let cornerRadius: CGFloat = 0.5
    static let endCornerRadius: CGFloat = 1

    static func length(at index: Int) -> CGFloat {
        index == 1 ? lightLength : endLightLength
    }

    static func cornerRadius(at index: Int) -> CGFloat {
        index == 1 ? cornerRadius : endCornerRadius
    }

    /// Distance from the row's centre to this light's centre, along the row.
    static func offsetAlongRow(at index: Int) -> CGFloat {
        switch index {
        case 0: return -(rowLength - endLightLength) / 2
        case 2: return (rowLength - endLightLength) / 2
        default: return 0
        }
    }
    static let glowBlur: CGFloat = 4
    static let waveStep: TimeInterval = 0.64
    static let flashOn: TimeInterval = 0.28
    static let flashPeriod: TimeInterval = 0.72
    /// Green blinks on arrival at `.finished`, then holds steady.
    static let finishBlinkPeriod: TimeInterval = 0.26
    static let finishBlinks = 3

    static var rowLength: CGFloat { endLightLength * 2 + lightLength + lightGap * 2 }

    static func lights(for agent: Agent, now: Date, reducedMotion: Bool) -> [LightColor] {
        if agent.currentTool != nil {
            return toolFlash(agent: agent, now: now, reducedMotion: reducedMotion)
        }
        switch agent.status {
        case .thinking, .working:
            return thinkingWave(now: now, reducedMotion: reducedMotion)
        case .waitingOnUser:
            return [.white, .white, .white]
        case .finished:
            return finishBlink(agent: agent, now: now, reducedMotion: reducedMotion)
        case .error:
            return [.red, .red, .red]
        case .idle:
            return [.off, .off, .off]
        }
    }

    static func viewFrame(marble: MarbleFrame, orientation: LineOrientation) -> CGRect {
        let centers = centers(marble: marble, orientation: orientation)
        let pad = glowBlur
        // The outermost centres belong to the end lights, so those set the
        // extent along the row.
        let halfX: CGFloat
        let halfY: CGFloat
        switch orientation.axis {
        case .vertical:
            halfX = endLightLength / 2
            halfY = lightThickness / 2
        case .horizontal:
            halfX = lightThickness / 2
            halfY = endLightLength / 2
        }
        let minX = (centers.map(\.x).min() ?? 0) - halfX - pad
        let maxX = (centers.map(\.x).max() ?? 0) + halfX + pad
        let minY = (centers.map(\.y).min() ?? 0) - halfY - pad
        let maxY = (centers.map(\.y).max() ?? 0) + halfY + pad
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func centers(marble: MarbleFrame, orientation: LineOrientation) -> [CGPoint] {
        let alongOffset = marble.size / 2 + LayoutEngine.indicatorGap + lightThickness / 2
        let along: CGFloat
        switch orientation.axis {
        case .vertical:
            along = orientation.indexIncreasesAlongPositive
                ? marble.center.y + alongOffset
                : marble.center.y - alongOffset
        case .horizontal:
            along = orientation.indexIncreasesAlongPositive
                ? marble.center.x + alongOffset
                : marble.center.x - alongOffset
        }
        return (0..<3).map { index in
            let offset = offsetAlongRow(at: index)
            switch orientation.axis {
            case .vertical:
                return CGPoint(x: marble.center.x + offset, y: along)
            case .horizontal:
                return CGPoint(x: along, y: marble.center.y - offset)
            }
        }
    }

    static func flashMask(seed: UInt64, toolID: String) -> [Bool] {
        var mixed = seed &+ 0x9E37_79B9_7F4A_7C15
        for byte in toolID.utf8 {
            mixed = mixed &* 131 &+ UInt64(byte)
        }
        let count = 1 + Int(mixed % 2)
        let start = Int((mixed >> 3) % 3)
        var mask = [false, false, false]
        for offset in 0..<count {
            mask[(start + offset) % 3] = true
        }
        return mask
    }

    /// Three green pulses on arrival, then solid green. Starts lit, so the row
    /// reads as on the instant the agent finishes rather than a beat later.
    private static func finishBlink(agent: Agent, now: Date, reducedMotion: Bool) -> [LightColor] {
        let solid: [LightColor] = [.green, .green, .green]
        guard !reducedMotion, let finishedAt = agent.finishedAt else { return solid }
        let elapsed = now.timeIntervalSince(finishedAt)
        guard elapsed >= 0, elapsed < Double(finishBlinks) * finishBlinkPeriod else { return solid }
        let phase = elapsed.truncatingRemainder(dividingBy: finishBlinkPeriod)
        return phase < finishBlinkPeriod / 2 ? solid : [.off, .off, .off]
    }

    private static func thinkingWave(now: Date, reducedMotion: Bool) -> [LightColor] {
        let step = reducedMotion ? 0 : Int(now.timeIntervalSinceReferenceDate / waveStep) % 3
        return (0..<3).map { $0 == step ? .white : .off }
    }

    private static func toolFlash(agent: Agent, now: Date, reducedMotion: Bool) -> [LightColor] {
        let id = agent.currentTool?.id ?? agent.id
        let mask = flashMask(seed: agent.seed, toolID: id)
        let on: Bool
        if reducedMotion {
            on = true
        } else {
            let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: flashPeriod)
            on = phase < flashOn
        }
        return mask.map { $0 && on ? .white : .off }
    }
}
