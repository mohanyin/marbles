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
/// attractor. Stops on a shared curve are relatives rather than strangers, and
/// spacing them by a fixed arc length keeps consecutive stops a fixed visible
/// distance apart no matter how fast the trajectory happens to be moving.
///
/// The walk runs in gamma-encoded sRGB: the three attractor coordinates are the
/// three colour channels. An earlier version walked in Oklab, which allowed
/// lightness, chroma and hue to be steered independently; measured side by side
/// at matched perceptual step size, this space produced more chroma (0.089 vs
/// 0.070), fewer near-grey stops (17% vs 27%) and better separation (2.45 vs
/// 1.68), so the simpler space won on results. What it gives up is control:
/// here the channels are welded together, so there is no lightness knob or
/// chroma knob to turn -- only `rgbCenter`, `rgbSpread` and `stepRange`, each of
/// which moves everything at once. The Oklab machinery is in git history if a
/// future change needs those axes back.
///
/// Walking in *linear* RGB instead is a trap worth naming: linear 0.5 displays
/// at about 0.74, so a cube centred on 0.5 comes out chalky, with more than
/// twice as many dead-grey stops.
///
/// The render target is `bgra8Unorm_srgb`, so the shader works in linear light
/// and the GPU encodes on write. Stops are therefore decoded to linear on the
/// way out, in `linearColor`.
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
    /// Arc length in gamma-encoded sRGB between consecutive stops. Drawn per
    /// marble: low values give a tonal marble, high values a wide-arc one, and
    /// that contrast is itself an identity cue. Scaled to hold the mean
    /// perceptual step at about deltaE 0.09, matching what the Oklab walk took.
    private static let stepRange: ClosedRange<Double> = 0.117...0.292
    /// Mid-cube. Stops ride outward from here along the attractor.
    private static let rgbCenter: Double = 0.5
    /// How far a marble ranges from `rgbCenter` in each channel. This is the
    /// nearest thing to a saturation control the space offers, and it moves
    /// lightness at the same time.
    private static let rgbSpread: ClosedRange<Double> = 0.30...0.50

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
        let spread = rng.value(in: rgbSpread)
        let step = rng.value(in: stepRange)
        let innerDistortion = 0.1 + rng.unit() * 0.7
        let size = 0.7 + rng.unit() * 0.3
        let angle = rng.unit() * 360

        for _ in 0..<warmupSteps {
            point = advance(point, dissipation: dissipation)
        }

        let scale = attractorScale(dissipation: dissipation)

        /// The attractor's three coordinates, straight onto the three channels.
        func channels(_ p: Vec3) -> Vec3 {
            Vec3(
                x: rgbCenter + spread * clampUnit(p.x / scale),
                y: rgbCenter + spread * clampUnit(p.y / scale),
                z: rgbCenter + spread * clampUnit(p.z / scale)
            )
        }

        // Two extra stops past the smoke ramp: the backdrop and the inner wash,
        // taken from the same walk so they stay in the family.
        var stops: [Vec3] = [channels(point)]
        let wanted = count + 2
        while stops.count < wanted {
            var travelled = 0.0
            var previous = channels(point)
            var steps = 0
            while travelled < step && steps < maxStepsPerStop {
                point = advance(point, dissipation: dissipation)
                let current = channels(point)
                travelled += distance(previous, current)
                previous = current
                steps += 1
            }
            stops.append(channels(point))
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

    // MARK: - Colour

    /// sRGB transfer function. The walk happens in encoded space, where equal
    /// steps read as equal visible differences; the shader wants linear light.
    private static func srgbDecode(_ v: Double) -> Double {
        let c = min(max(v, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func linearColor(_ c: Vec3, alpha: Float) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(srgbDecode(c.x)),
            Float(srgbDecode(c.y)),
            Float(srgbDecode(c.z)),
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
