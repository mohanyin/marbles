import Foundation

enum DemoMarble {
    static let id = "demo-first-run"
    static let discoveryWindow: TimeInterval = 2 * 60 * 60

    static func shouldOffer(demoOffered: Bool, recentActivity: Bool) -> Bool {
        !demoOffered && !recentActivity
    }

    static func make() -> Agent {
        Agent.make(
            id: id,
            source: .demo,
            status: .working,
            lastAssistantPreview: "Demo.",
            title: "Demo.",
            seed: Identity.seed(forDebugIndex: 0),
            isDemo: true
        )
    }
}
