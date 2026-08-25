import Foundation

enum DemoTests {
    static func run() {
        offerRules()
        discoveryWindow()
        previewLabel()
    }

    private static func offerRules() {
        TestRun.expect(DemoMarble.shouldOffer(demoOffered: false, recentActivity: false), "first empty launch")
        TestRun.expect(!DemoMarble.shouldOffer(demoOffered: false, recentActivity: true), "skip when discovery is warm")
        TestRun.expect(!DemoMarble.shouldOffer(demoOffered: true, recentActivity: false), "do not refill later")
    }

    private static func discoveryWindow() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("marbles-disc-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("session.jsonl")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "x\n".write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: file.path
        )
        TestRun.expect(SessionDiscovery.hasRecentClaudeActivity(projects: root), "fresh jsonl counts")

        let stale = FileManager.default.temporaryDirectory.appendingPathComponent("marbles-disc-\(UUID().uuidString)", isDirectory: true)
        let old = stale.appendingPathComponent("old.jsonl")
        try? FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try? "x\n".write(to: old, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3 * 60 * 60)],
            ofItemAtPath: old.path
        )
        TestRun.expect(!SessionDiscovery.hasRecentClaudeActivity(projects: stale), "stale jsonl ignored")
    }

    private static func previewLabel() {
        TestRun.expectEqual(FocusPreview.title(for: DemoMarble.make()), "Demo.")
    }
}
