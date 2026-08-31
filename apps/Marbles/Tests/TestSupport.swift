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

/// A mid-sized card: title + a one-line prompt + a few lines of response.
let sampleCardSize = FocusCardMetrics.size(
    title: "Session",
    prompt: "Fix the layout",
    response: String(repeating: "response line\n", count: 4)
)

/// Both text regions maxed out at their scroll caps.
let maxCardSize = FocusCardMetrics.size(
    title: "Session",
    prompt: String(repeating: "prompt ", count: 400),
    response: String(repeating: "response ", count: 2000)
)

func dockLayout(
    _ agents: [Agent],
    mode: OverlayMode = .dock,
    scrollOffset: CGFloat = 0,
    available: CGFloat = 900,
    cardSize: CGSize = sampleCardSize
) -> LayoutResult {
    LayoutEngine.layout(
        agents: agents,
        mode: mode,
        orientation: LineOrientation(axis: .vertical, indexIncreasesAlongPositive: false),
        scrollOffset: scrollOffset,
        availableLineLength: available,
        cardTowardPositivePerpendicular: false,
        focusCardSize: cardSize
    )
}

func agents(count: Int) -> [Agent] {
    (0..<count).map { Agent.debugDummy(index: $0) }
}
