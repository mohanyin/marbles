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

/// Marble palettes are stops along one trajectory of Thomas' cyclically symmetric
/// attractor, walked in Oklab. Two properties come from that: stops on a shared
/// curve are relatives rather than strangers, and Oklab arc length is perceptual
/// distance, so spacing stops by a fixed arc length spaces them by a fixed
/// visible difference no matter how fast the trajectory happens to be moving.
///
/// The render target is `bgra8Unorm_srgb`, so the shader works in linear light
/// and the GPU encodes on write. Colors here are therefore linear, not
/// sRGB-encoded.
enum Identity {
    static let minColors = 3
    static let maxColors = 5

    /// Chaotic, bounded, and non-divergent across this whole interval — the
    /// reason Thomas is usable with a randomized parameter where most
    /// attractors need a stability search per seed.
    private static let dissipationRange: ClosedRange<Double> = 0.10...0.20
    /// The attractor's extent depends on its dissipation: |max| runs from about
    /// 6.0 at b = 0.10 down to 3.9 at b = 0.20, fitting 1.9 / sqrt(b) to within
    /// ~10%. A single hardcoded scale mis-sized a range that varies 2.4x, so low
    /// dissipation marbles spent stretches pinned against the clamp with their
    /// colour flat. `clampUnit` stays as a guard for the fit's error margin.
    private static func attractorScale(dissipation: Double) -> Double {
        1.9 / dissipation.squareRoot()
    }
    /// Oklab arc length between consecutive stops. Drawn per marble: low values
    /// give a tonal marble, high values a wide-arc one, and that contrast is
    /// itself an identity cue.
    private static let stepRange: ClosedRange<Double> = 0.08...0.20
    private static let lightnessCenter: Double = 0.58
    private static let lightnessJitter: Double = 0.06
    /// Lightness travel inside one marble. The walk itself is isotropic — a
    /// measured 34% of each step's squared displacement lands on the L axis
    /// against 33% for perfectly even — so the only thing that was holding
    /// lightness flat was this budget. Widening it is what gives a marble
    /// light and dark within one disc instead of a single tone.
    private static let lightnessAmplitude: ClosedRange<Double> = 0.18...0.34
    /// Chroma as a share of what sRGB can actually supply at this hue and
    /// lightness, rather than an absolute amount the gamut may not be able to
    /// meet. Replaces the old absolute budget, which asked every hue for the
    /// same chroma and let clipping quietly flatten the ones that could not.
    private static let chromaFraction: ClosedRange<Double> = 0.55...0.85
    /// How far each stop's lightness is pulled toward the gamut cusp for its own
    /// hue. Every hue peaks at a different lightness -- yellow near 0.86, blue
    /// near 0.46 -- so a band pinned at 0.58 asks yellow for a colour sRGB
    /// cannot make, and it lands as olive. Kept low: cusp lightness sits above
    /// 0.58 for most of the wheel, so bias buys warm hues at the cost of the
    /// dark end. 0.25 is a nudge, not a rebalance.
    private static let cuspBias: Double = 0.25

    private static let integrationStep: Double = 0.01
    private static let warmupSteps = 1_500
    private static let maxStepsPerStop = 20_000

    private static let cacheLock = NSLock()
    private static var cache: [UInt64: MarbleParams] = [:]
    private static let cacheLimit = 1_024

    static func params(seed: UInt64) -> MarbleParams {
        cacheLock.lock()
        if let hit = cache[seed] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let made = makeParams(seed: seed)

        cacheLock.lock()
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[seed] = made
        cacheLock.unlock()
        return made
    }

    /// The color count without walking the curve, so seed searches stay cheap.
    static func colorCount(seed: UInt64) -> Int {
        var rng = SplitMix(seed: seed)
        return drawColorCount(&rng)
    }

    private static func drawColorCount(_ rng: inout SplitMix) -> Int {
        let span = maxColors - minColors + 1
        return min(minColors + Int(rng.unit() * Double(span)), maxColors)
    }

    private static func makeParams(seed: UInt64) -> MarbleParams {
        var rng = SplitMix(seed: seed)

        // Count is drawn first so `colorCount(seed:)` can stop right here.
        let count = drawColorCount(&rng)
        let dissipation = rng.value(in: dissipationRange)
        var point = Vec3(
            x: rng.value(in: -2...2),
            y: rng.value(in: -2...2),
            z: rng.value(in: -2...2)
        )
        let lightness = lightnessCenter + rng.value(in: -lightnessJitter...lightnessJitter)
        let amplitude = rng.value(in: lightnessAmplitude)
        let fraction = rng.value(in: chromaFraction)
        let step = rng.value(in: stepRange)
        let innerDistortion = 0.1 + rng.unit() * 0.7
        let size = 0.7 + rng.unit() * 0.3
        let angle = rng.unit() * 360

        for _ in 0..<warmupSteps {
            point = advance(point, dissipation: dissipation)
        }

        let scale = attractorScale(dissipation: dissipation)

        func lab(_ p: Vec3) -> Vec3 {
            let walked = lightness + amplitude * clampUnit(p.z / scale)
            let hx = p.x / scale, hy = p.y / scale
            let radius = min((hx * hx + hy * hy).squareRoot(), 1)
            let angle = atan2(hy, hx)
            let ca = cos(angle), sa = sin(angle)
            let L = walked * (1 - cuspBias) + cuspLightness(angle: angle) * cuspBias
            let c = fraction * radius * maxChroma(lightness: L, ca: ca, sa: sa)
            return Vec3(x: L, y: c * ca, z: c * sa)
        }

        // Two extra stops past the smoke ramp: the backdrop and the inner wash,
        // taken from the same walk so they stay in the family.
        var stops: [Vec3] = [lab(point)]
        let wanted = count + 2
        while stops.count < wanted {
            var travelled = 0.0
            var previous = lab(point)
            var steps = 0
            while travelled < step && steps < maxStepsPerStop {
                point = advance(point, dissipation: dissipation)
                let current = lab(point)
                travelled += distance(previous, current)
                previous = current
                steps += 1
            }
            stops.append(lab(point))
        }

        let colors = stops.prefix(count).map { linearColor($0, alpha: 1) }
        return MarbleParams(
            colors: Array(colors),
            colorBack: linearColor(stops[count], alpha: 1),
            colorInner: linearColor(stops[count + 1], alpha: 0),
            innerDistortion: Float(innerDistortion),
            size: Float(size),
            angle: Float(angle)
        )
    }

    // MARK: - Attractor

    private struct Vec3 {
        var x: Double
        var y: Double
        var z: Double
    }

    private static func derivative(_ p: Vec3, dissipation b: Double) -> Vec3 {
        Vec3(
            x: sin(p.y) - b * p.x,
            y: sin(p.z) - b * p.y,
            z: sin(p.x) - b * p.z
        )
    }

    private static func advance(_ p: Vec3, dissipation: Double) -> Vec3 {
        let h = integrationStep
        let k1 = derivative(p, dissipation: dissipation)
        let k2 = derivative(offset(p, k1, h / 2), dissipation: dissipation)
        let k3 = derivative(offset(p, k2, h / 2), dissipation: dissipation)
        let k4 = derivative(offset(p, k3, h), dissipation: dissipation)
        return Vec3(
            x: p.x + h / 6 * (k1.x + 2 * k2.x + 2 * k3.x + k4.x),
            y: p.y + h / 6 * (k1.y + 2 * k2.y + 2 * k3.y + k4.y),
            z: p.z + h / 6 * (k1.z + 2 * k2.z + 2 * k3.z + k4.z)
        )
    }

    private static func offset(_ p: Vec3, _ d: Vec3, _ h: Double) -> Vec3 {
        Vec3(x: p.x + h * d.x, y: p.y + h * d.y, z: p.z + h * d.z)
    }

    private static func distance(_ a: Vec3, _ b: Vec3) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    private static func clampUnit(_ v: Double) -> Double {
        min(max(v, -1), 1)
    }

    // MARK: - Oklab

    private static func oklabToLinear(_ c: Vec3) -> (Double, Double, Double) {
        let l = pow3(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z)
        let m = pow3(c.x - 0.1055613458 * c.y - 0.0638541728 * c.z)
        let s = pow3(c.x - 0.0894841775 * c.y - 1.2914855480 * c.z)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    private static func pow3(_ v: Double) -> Double { v * v * v }

    /// Lightness of the sRGB gamut cusp per hue -- the lightness at which that
    /// hue reaches its highest chroma. Sampled once on first use.
    private static let cuspTable: [Double] = (0..<64).map { i in
        let h = Double(i) / 64 * 2 * .pi
        let ca = cos(h), sa = sin(h)
        var bestL = 0.5
        var bestC = -1.0
        var L = 0.05
        while L < 0.99 {
            let c = maxChroma(lightness: L, ca: ca, sa: sa)
            if c > bestC { bestC = c; bestL = L }
            L += 0.01
        }
        return bestL
    }

    private static func cuspLightness(angle: Double) -> Double {
        var turns = angle / (2 * .pi)
        turns -= turns.rounded(.down)
        let x = turns * 64
        let i = Int(x) % 64
        let f = x - Double(Int(x))
        return cuspTable[i] * (1 - f) + cuspTable[(i + 1) % 64] * f
    }

    /// Largest in-gamut chroma at this lightness and hue direction.
    private static func maxChroma(lightness L: Double, ca: Double, sa: Double) -> Double {
        var low = 0.0
        var high = 0.4
        if inGamut(Vec3(x: L, y: ca * high, z: sa * high)) { return high }
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if inGamut(Vec3(x: L, y: ca * mid, z: sa * mid)) { low = mid } else { high = mid }
        }
        return low
    }

    private static func inGamut(_ c: Vec3) -> Bool {
        let (r, g, b) = oklabToLinear(c)
        let epsilon = 1e-4
        return r >= -epsilon && r <= 1 + epsilon
            && g >= -epsilon && g <= 1 + epsilon
            && b >= -epsilon && b <= 1 + epsilon
    }

    /// Pull chroma in until the color fits sRGB, keeping lightness and hue.
    private static func gamutClip(_ c: Vec3) -> Vec3 {
        if inGamut(c) { return c }
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if inGamut(Vec3(x: c.x, y: c.y * mid, z: c.z * mid)) { low = mid } else { high = mid }
        }
        return Vec3(x: c.x, y: c.y * low, z: c.z * low)
    }

    private static func linearColor(_ c: Vec3, alpha: Float) -> SIMD4<Float> {
        let (r, g, b) = oklabToLinear(gamutClip(c))
        return SIMD4<Float>(
            Float(min(max(r, 0), 1)),
            Float(min(max(g, 0), 1)),
            Float(min(max(b, 0), 1)),
            alpha
        )
    }

    // MARK: - Seeding

    private struct SplitMix {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> Double {
            Double(next() % 10_000) / 10_000
        }

        mutating func value(in range: ClosedRange<Double>) -> Double {
            range.lowerBound + unit() * (range.upperBound - range.lowerBound)
        }
    }

    static func seed(forDebugIndex index: Int) -> UInt64 {
        UInt64(index &+ 1) &* 0x9E37_79B9_7F4A_7C15 &+ 17
    }

    static func sheetSeed(at index: Int) -> UInt64 {
        UInt64(index) &* 1_000_003 &+ 17
    }

    static func seeds(colorCount count: Int, count wanted: Int) -> [UInt64] {
        var found: [UInt64] = []
        var seed: UInt64 = 0
        while found.count < wanted, seed < 100_000 {
            if colorCount(seed: seed) == count {
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
