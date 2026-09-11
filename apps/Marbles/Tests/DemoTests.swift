import Foundation

enum DemoTests {
    static func run() {
        offerRules()
        discoveryWindow()
        scanRequiresLiveProcess()
        scanSkipsStaleTranscripts()
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

    /// A transcript alone is not a live session: without a matching process there is no marble.
    private static func scanRequiresLiveProcess() {
        let (root, _) = fixture(cwd: "/tmp/marbles-nowhere", age: 0)
        TestRun.expect(
            SessionDiscovery.scan(root: root, pids: []).isEmpty,
            "no live process means no discovered agent"
        )
    }

    /// A process whose cwd matches, but whose transcript is old, is a leftover — not a session.
    /// The current process is used as the live one, so its real cwd is what the fixture records.
    private static func scanSkipsStaleTranscripts() {
        let cwd = FileManager.default.currentDirectoryPath
        let me = ProcessInfo.processInfo.processIdentifier

        let (fresh, _) = fixture(cwd: cwd, age: 0)
        TestRun.expectEqual(
            SessionDiscovery.scan(root: fresh, pids: [me]).count,
            1,
            "a fresh transcript whose cwd matches a live process is discovered"
        )

        let (stale, _) = fixture(cwd: cwd, age: SessionDiscovery.freshness + 600)
        TestRun.expect(
            SessionDiscovery.scan(root: stale, pids: [me]).isEmpty,
            "a transcript older than the freshness window is ignored"
        )
    }

    /// A projects directory holding one transcript that records `cwd`, aged `age` seconds.
    private static func fixture(cwd: String, age: TimeInterval) -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("marbles-scan-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("\(UUID().uuidString).jsonl")
        let line = #"{"type":"user","cwd":"\#(cwd)","message":{"role":"user","content":"hello"}}"# + "\n"
        try? line.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)],
            ofItemAtPath: file.path
        )
        return (root, file)
    }
}
