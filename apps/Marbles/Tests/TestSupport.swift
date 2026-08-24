import Foundation

enum TestRun {
    private(set) static var failures = 0

    static func expect(_ condition: Bool, _ message: String, file: StaticString = #fileID, line: Int = #line) {
        if !condition {
            failures += 1
            print("FAIL \(file):\(line) — \(message)")
        }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #fileID, line: Int = #line) {
        let suffix = message.isEmpty ? "" : " \(message)"
        expect(actual == expected, "expected \(expected), got \(actual)\(suffix)", file: file, line: line)
    }

    static func expectNear(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.5, _ message: String = "", file: StaticString = #fileID, line: Int = #line) {
        let suffix = message.isEmpty ? "" : " \(message)"
        expect(
            abs(actual - expected) <= tolerance,
            "expected \(expected) ±\(tolerance), got \(actual)\(suffix)",
            file: file,
            line: line
        )
    }
}

func clusterLayout(_ agents: [Agent]) -> LayoutResult {
    LayoutEngine.layout(
        agents: agents,
        mode: .cluster,
        orientation: LineOrientation(axis: .vertical, indexIncreasesAlongPositive: true),
        scrollOffset: 0,
        availableLineLength: 900,
        cardTowardPositivePerpendicular: true
    )
}

func lineLayout(_ agents: [Agent], mode: OverlayMode = .active) -> LayoutResult {
    LayoutEngine.layout(
        agents: agents,
        mode: mode,
        orientation: LineOrientation(axis: .vertical, indexIncreasesAlongPositive: true),
        scrollOffset: 0,
        availableLineLength: 900,
        cardTowardPositivePerpendicular: true
    )
}

func agents(count: Int) -> [Agent] {
    var next = (0..<count).map { Agent.debugDummy(index: $0) }
    LatticeSlots.assign(&next)
    return next
}
