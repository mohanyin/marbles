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

enum SessionDiscovery {
    static func hasRecentClaudeActivity(
        now: Date = Date(),
        window: TimeInterval = DemoMarble.discoveryWindow,
        projects: URL? = nil
    ) -> Bool {
        let root = projects ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        let cutoff = now.addingTimeInterval(-window)
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date >= cutoff {
                return true
            }
        }
        return false
    }
}
