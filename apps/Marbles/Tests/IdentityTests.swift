import Foundation
import simd

enum IdentityTests {
    static func run() {
        sameSeedIsDeterministic()
        paramsStayInRange()
        colorCountsCoverRange()
        nextSeedChangesPalette()
        debugSeedsAreDistinct()
        paletteWalkProducesDistinctStops()
        paletteStaysCohesive()
    }

    private static func sameSeedIsDeterministic() {
        let a = Identity.params(seed: 42)
        let b = Identity.params(seed: 42)
        TestRun.expectEqual(a, b, "params(seed) is pure")
    }

    private static func paramsStayInRange() {
        for seed: UInt64 in [0, 1, 21, 50, 99, 4_294_967_291] {
            let p = Identity.params(seed: seed)
            TestRun.expect(
                p.colors.count >= Identity.minColors && p.colors.count <= Identity.maxColors,
                "color count \(p.colors.count) seed \(seed)"
            )
            TestRun.expectEqual(p.colorBack.w, 1, "colorBack is opaque")
            TestRun.expect(p.innerDistortion >= 0.1 && p.innerDistortion <= 0.8, "distortion \(p.innerDistortion)")
            TestRun.expect(p.size >= 0.7 && p.size <= 1, "size \(p.size)")
            TestRun.expect(p.angle >= 0 && p.angle <= 360, "angle \(p.angle)")
            for color in p.colors {
                TestRun.expectEqual(color.w, 1, "smoke color alpha")
                TestRun.expect(color.x >= 0 && color.x <= 1, "r \(color.x)")
                TestRun.expect(color.y >= 0 && color.y <= 1, "g \(color.y)")
                TestRun.expect(color.z >= 0 && color.z <= 1, "b \(color.z)")
            }
        }
    }

    private static func colorCountsCoverRange() {
        var seen = Set<Int>()
        for index in 0..<80 {
            seen.insert(Identity.params(seed: Identity.sheetSeed(at: index)).colors.count)
        }
        TestRun.expect(seen.contains(3), "sheet seeds include 3 colors")
        TestRun.expect(seen.contains(4), "sheet seeds include 4 colors")
        TestRun.expect(seen.contains(5), "sheet seeds include 5 colors")
        for count in Identity.minColors...Identity.maxColors {
            TestRun.expectEqual(Identity.seeds(colorCount: count, count: 8).count, 8, "\(count) color seeds")
        }
    }

    private static func nextSeedChangesPalette() {
        let seed: UInt64 = 10
        let next = Identity.nextSeed(seed)
        TestRun.expect(Identity.params(seed: next) != Identity.params(seed: seed), "cycle changes palette")
    }

    /// A stalled walk would hand back the same point repeatedly, which reads as
    /// a flat marble rather than an obvious crash.
    private static func paletteWalkProducesDistinctStops() {
        for index in 0..<40 {
            let p = Identity.params(seed: Identity.sheetSeed(at: index))
            for i in 1..<p.colors.count {
                let d = simd_distance(p.colors[i - 1], p.colors[i])
                TestRun.expect(d > 0.001, "stop \(i) moved, seed index \(index)")
            }
            TestRun.expect(
                simd_distance(p.colors[p.colors.count - 1], p.colorBack) > 0.001,
                "colorBack differs from last stop, seed index \(index)"
            )
        }
    }

    /// The point of the attractor walk: stops inside one marble sit closer
    /// together than independently drawn colors would. Random RGB averages well
    /// above this bound, so the check fails if the walk is bypassed.
    private static func paletteStaysCohesive() {
        var total: Float = 0
        var seen = 0
        for index in 0..<40 {
            let p = Identity.params(seed: Identity.sheetSeed(at: index))
            var centroid = SIMD4<Float>(repeating: 0)
            for c in p.colors { centroid += c }
            centroid /= Float(p.colors.count)
            for c in p.colors {
                total += simd_distance(SIMD3<Float>(c.x, c.y, c.z), SIMD3<Float>(centroid.x, centroid.y, centroid.z))
                seen += 1
            }
        }
        let mean = total / Float(seen)
        TestRun.expect(mean < 0.30, "mean within-marble spread \(mean) stays cohesive")
    }

    private static func debugSeedsAreDistinct() {
        var seen = Set<UInt64>()
        for index in 0..<12 {
            seen.insert(Identity.seed(forDebugIndex: index))
        }
        TestRun.expectEqual(seen.count, 12, "debug inject seeds are unique")
    }
}
