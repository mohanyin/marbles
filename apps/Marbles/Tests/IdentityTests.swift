import Foundation

enum IdentityTests {
    static func run() {
        sameSeedIsDeterministic()
        familyTable()
        paramsStayInRange()
        huesStayPleasant()
        pairsStayHarmonized()
        accentIsDistinctAndPleasant()
        sheetSeedsCoverEveryFamily()
        familySeedsStayInFamily()
        nextSeedChangesFamily()
        debugSeedsSpreadFamilies()
    }

    private static func sameSeedIsDeterministic() {
        let a = Identity.params(seed: 42)
        let b = Identity.params(seed: 42)
        TestRun.expectEqual(a, b, "params(seed) is pure")
    }

    private static func familyTable() {
        let cases: [(UInt64, InteriorFamily)] = [
            (0, .silk), (21, .silk),
            (22, .crystal), (42, .crystal),
            (43, .prism), (60, .prism),
            (61, .nebula), (78, .nebula),
            (79, .core), (88, .core),
            (89, .landscape), (99, .landscape),
            (100, .silk),
        ]
        for (seed, expected) in cases {
            TestRun.expectEqual(Identity.family(for: seed), expected, "seed \(seed)")
        }
    }

    private static func paramsStayInRange() {
        for seed: UInt64 in [0, 1, 21, 50, 99, 4_294_967_291] {
            let p = Identity.params(seed: seed)
            TestRun.expect(p.hue >= 0 && p.hue <= 1, "hue \(p.hue)")
            TestRun.expect(p.saturation >= 0.58 && p.saturation <= 0.95, "sat \(p.saturation)")
            TestRun.expect(p.frost >= 0.06 && p.frost <= 0.35, "frost \(p.frost)")
            TestRun.expect(p.luminosity >= 0.55 && p.luminosity <= 0.96, "lum \(p.luminosity)")
        }
    }

    private static func huesStayPleasant() {
        for t in stride(from: Float(0), through: 1, by: 0.05) {
            let hue = Identity.pleasantHue(t)
            TestRun.expect(hue <= 0.11 || hue >= 0.49, "no chartreuse \(hue)")
        }
    }

    private static func accentIsDistinctAndPleasant() {
        for seed: UInt64 in 0..<120 {
            let p = Identity.params(seed: seed)
            TestRun.expect(p.accentHue <= 0.11 || p.accentHue >= 0.49, "accent chartreuse \(p.accentHue)")
            let fromHue = min(abs(p.accentHue - p.hue), 1 - abs(p.accentHue - p.hue))
            let fromSecondary = min(abs(p.accentHue - p.secondaryHue), 1 - abs(p.accentHue - p.secondaryHue))
            TestRun.expect(fromHue >= 0.14, "accent vs hue \(fromHue) seed \(seed)")
            TestRun.expect(fromSecondary >= 0.10, "accent vs secondary \(fromSecondary) seed \(seed)")
        }
    }

    private static func pairsStayHarmonized() {
        for seed: UInt64 in 0..<80 {
            let p = Identity.params(seed: seed)
            let delta = abs(p.secondaryHue - p.hue)
            let d = min(delta, 1 - delta)
            TestRun.expect(d >= 0.04 && d <= 0.56, "pair distance \(d) seed \(seed)")
        }
    }

    private static func sheetSeedsCoverEveryFamily() {
        var seen = Set<InteriorFamily>()
        for index in 0..<100 {
            seen.insert(Identity.family(for: Identity.sheetSeed(at: index)))
        }
        TestRun.expectEqual(seen.count, InteriorFamily.allCases.count, "100 sheet seeds hit every family")
    }

    private static func nextSeedChangesFamily() {
        let seed: UInt64 = 10
        let next = Identity.nextSeed(seed)
        TestRun.expect(Identity.family(for: next) != Identity.family(for: seed), "cycle changes family")
    }

    private static func familySeedsStayInFamily() {
        for family in InteriorFamily.allCases {
            for seed in Identity.seeds(for: family, count: 12) {
                TestRun.expectEqual(Identity.family(for: seed), family, "seed \(seed) is \(family.displayName)")
            }
        }
    }

    private static func debugSeedsSpreadFamilies() {
        var seen = Set<InteriorFamily>()
        for index in 0..<12 {
            seen.insert(Identity.family(for: Identity.seed(forDebugIndex: index)))
        }
        TestRun.expect(seen.count >= 5, "debug inject covers most families")
    }
}
