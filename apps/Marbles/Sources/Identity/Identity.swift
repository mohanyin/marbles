import Foundation
import simd

struct MarbleParams: Equatable {
    var colors: [SIMD4<Float>]
    var colorBack: SIMD4<Float>
    var colorInner: SIMD4<Float>
    var innerDistortion: Float
    var size: Float
    var angle: Float
}

enum Identity {
    static let minColors = 3
    static let maxColors = 5

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
        func color(alpha: Float) -> SIMD4<Float> {
            SIMD4<Float>(unit(), unit(), unit(), alpha)
        }
        let count = minColors + Int(unit() * Float(maxColors - minColors + 1))
        let clamped = min(max(count, minColors), maxColors)
        let colors = (0..<clamped).map { _ in color(alpha: 1) }
        return MarbleParams(
            colors: colors,
            colorBack: color(alpha: 1),
            colorInner: color(alpha: 0),
            innerDistortion: 0.1 + unit() * 0.7,
            size: 0.7 + unit() * 0.3,
            angle: unit() * 360
        )
    }

    static func seed(forDebugIndex index: Int) -> UInt64 {
        UInt64(index &+ 1) &* 0x9E37_79B9_7F4A_7C15 &+ 17
    }

    static func sheetSeed(at index: Int) -> UInt64 {
        UInt64(index) &* 1_000_003 &+ 17
    }

    static func seeds(colorCount: Int, count: Int) -> [UInt64] {
        var found: [UInt64] = []
        var seed: UInt64 = 0
        while found.count < count, seed < 100_000 {
            if params(seed: seed).colors.count == colorCount {
                found.append(seed)
            }
            seed += 1
        }
        return found
    }

    static func nextSeed(_ seed: UInt64) -> UInt64 {
        seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
    }
}
