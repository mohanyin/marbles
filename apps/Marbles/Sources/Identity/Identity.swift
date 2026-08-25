import Foundation
import simd

enum InteriorFamily: UInt8, CaseIterable, Equatable {
    case silk
    case crystal
    case prism
    case nebula
    case landscape
    case core

    var displayName: String {
        switch self {
        case .silk: return "Silk"
        case .crystal: return "Crystal"
        case .prism: return "Prism"
        case .nebula: return "Nebula"
        case .landscape: return "Landscape"
        case .core: return "Core"
        }
    }

    var seedResidue: ClosedRange<UInt64> {
        switch self {
        case .silk: return 0...21
        case .crystal: return 22...42
        case .prism: return 43...60
        case .nebula: return 61...78
        case .core: return 79...88
        case .landscape: return 89...99
        }
    }
}

struct MarbleParams: Equatable {
    var family: InteriorFamily
    var hue: Float
    var saturation: Float
    var frost: Float
    var inclusionDensity: Float
    var luminosity: Float
    var secondaryHue: Float
    var noiseOffset: SIMD3<Float>
    var accentHue: Float
}

enum Identity {
    static func family(for seed: UInt64) -> InteriorFamily {
        let residue = seed % 100
        return InteriorFamily.allCases.first { $0.seedResidue.contains(residue) } ?? .landscape
    }

    static func params(seed: UInt64) -> MarbleParams {
        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func unit() -> Float {
            Float(next() % 10_000) / 10_000
        }
        let kind = family(for: seed)
        let hue = pleasantHue(unit())
        let complementary = kind == .crystal || kind == .core || kind == .landscape
        let saturation = complementary ? 0.58 + unit() * 0.28 : 0.64 + unit() * 0.30
        let frost = 0.06 + unit() * 0.28
        let inclusionDensity = 0.12 + unit() * 0.78
        let luminosity = 0.55 + unit() * 0.40
        let secondary = secondaryHue(family: kind, hue: hue, swing: unit())
        let noiseOffset = SIMD3<Float>(unit() * 8 - 4, unit() * 8 - 4, unit() * 8 - 4)
        return MarbleParams(
            family: kind,
            hue: hue,
            saturation: saturation,
            frost: frost,
            inclusionDensity: inclusionDensity,
            luminosity: luminosity,
            secondaryHue: secondary,
            noiseOffset: noiseOffset,
            accentHue: accentHue(hue: hue, secondary: secondary, swing: unit())
        )
    }

    /// Skip chartreuse / sick yellow-green; sit in reds, golds, teals, blues, violets.
    static func pleasantHue(_ t: Float) -> Float {
        let warm: [Float] = [0.00, 0.035, 0.07, 0.10]
        let cool: [Float] = [0.50, 0.56, 0.63, 0.73, 0.82, 0.93]
        if t < 0.38 {
            return lerpStops(warm, t / 0.38)
        }
        return lerpStops(cool, (t - 0.38) / 0.62)
    }

    private static func lerpStops(_ stops: [Float], _ t: Float) -> Float {
        let scaled = min(max(t, 0), 0.9999) * Float(stops.count - 1)
        let index = Int(scaled)
        let f = scaled - Float(index)
        let u = f * f * (3 - 2 * f)
        return stops[index] + (stops[index + 1] - stops[index]) * u
    }

    /// Analogous for silk/nebula, complement for crystal/core, split-comp for landscape.
    static func secondaryHue(family: InteriorFamily, hue: Float, swing: Float) -> Float {
        let offset: Float
        switch family {
        case .silk, .nebula:
            offset = 0.05 + swing * 0.09
        case .prism:
            offset = 0.14 + swing * 0.08
        case .crystal:
            offset = 0.46 + swing * 0.06
        case .landscape:
            offset = 0.42 + swing * 0.10
        case .core:
            offset = 0.48 + swing * 0.05
        }
        let value = hue + offset
        return value - floor(value)
    }

    /// Pleasant stop farthest from both primary and secondary so the third color
    /// stays distinct and never lands in the chartreuse gap.
    static func accentHue(hue: Float, secondary: Float, swing: Float) -> Float {
        let candidates: [Float] = [0.00, 0.035, 0.07, 0.10, 0.50, 0.56, 0.63, 0.73, 0.82, 0.93]
        func dist(_ a: Float, _ b: Float) -> Float {
            let delta = abs(a - b)
            return min(delta, 1 - delta)
        }
        let ranked = candidates.sorted { lhs, rhs in
            let a = min(dist(lhs, hue), dist(lhs, secondary))
            let b = min(dist(rhs, hue), dist(rhs, secondary))
            if a != b { return a > b }
            return lhs < rhs
        }
        return swing < 0.5 ? ranked[0] : ranked[1]
    }

    static func seed(forDebugIndex index: Int) -> UInt64 {
        let picks: [UInt64] = [7, 18, 28, 35, 48, 55, 65, 72, 82, 86, 92, 97]
        let familyPick = picks[index % picks.count]
        let rest = UInt64(index &+ 1) &* 0x9E37_79B9_7F4A_7C15
        return rest / 100 * 100 + familyPick
    }

    static func sheetSeed(at index: Int) -> UInt64 {
        UInt64(index) &* 1_000_003 &+ 17
    }

    static func seeds(for family: InteriorFamily, count: Int) -> [UInt64] {
        let range = family.seedResidue
        let span = range.upperBound - range.lowerBound + 1
        return (0..<count).map { index in
            range.lowerBound + UInt64(index) % span + UInt64(index) * 100
        }
    }

    static func nextSeed(_ seed: UInt64) -> UInt64 {
        let current = family(for: seed)
        var next = seed &+ 1
        var guardCount = 0
        while family(for: next) == current, guardCount < 100 {
            next &+= 1
            guardCount += 1
        }
        return next
    }
}
