import Foundation
import AppKit

enum LightColor: Equatable {
    case off
    case white
    case green
    case red
}

enum Indicators {
    static let lightSize: CGFloat = 3
    static let lightGap: CGFloat = 1
    static let cornerRadius: CGFloat = 0.5
    static let glowBlur: CGFloat = 4
    static let waveStep: TimeInterval = 0.64
    static let flashOn: TimeInterval = 0.28
    static let flashPeriod: TimeInterval = 0.72

    static var rowLength: CGFloat { lightSize * 3 + lightGap * 2 }

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
            return [.green, .green, .green]
        case .error:
            return [.red, .red, .red]
        case .idle:
            return [.off, .off, .off]
        }
    }

    static func viewFrame(marble: MarbleFrame, orientation: LineOrientation) -> CGRect {
        let centers = centers(marble: marble, orientation: orientation)
        let pad = glowBlur
        let minX = (centers.map(\.x).min() ?? 0) - lightSize / 2 - pad
        let maxX = (centers.map(\.x).max() ?? 0) + lightSize / 2 + pad
        let minY = (centers.map(\.y).min() ?? 0) - lightSize / 2 - pad
        let maxY = (centers.map(\.y).max() ?? 0) + lightSize / 2 + pad
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func centers(marble: MarbleFrame, orientation: LineOrientation) -> [CGPoint] {
        let alongOffset = marble.size / 2 + LayoutEngine.indicatorGap + lightSize / 2
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
        let spread = lightSize + lightGap
        return (0..<3).map { index in
            switch orientation.axis {
            case .vertical:
                return CGPoint(x: marble.center.x + CGFloat(index - 1) * spread, y: along)
            case .horizontal:
                return CGPoint(x: along, y: marble.center.y + CGFloat(1 - index) * spread)
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
