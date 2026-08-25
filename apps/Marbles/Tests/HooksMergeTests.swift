import Foundation

enum HooksMergeTests {
    static func run() {
        jsoncStripsCommentsButKeepsStrings()
        mergeCreatesBothFiles()
        mergeIsIdempotent()
        undoRemovesOnlyOurs()
        commentsSurvive()
        invalidFileIsLeftAlone()
        cursorKeepsVersion()
    }

    private static func jsoncStripsCommentsButKeepsStrings() {
        let text = """
        {
          // keep
          "url": "https://example.com/path//not-comment",
          /* block */
          "ok": true
        }
        """
        let object = try? JSONC.parseObject(text)
        TestRun.expectEqual(object?["ok"] as? Bool, true, "jsonc parses")
        TestRun.expectEqual(object?["url"] as? String, "https://example.com/path//not-comment", "slashes in strings stay")
    }

    private static func mergeCreatesBothFiles() {
        let files = tempFiles()
        try? Hooks.install(files: files)
        let state = Hooks.inspect(files: files)
        TestRun.expectEqual(state.claude, .installed, "claude installed")
        TestRun.expectEqual(state.cursor, .installed, "cursor installed")
        let claude = (try? String(contentsOf: files.claude, encoding: .utf8)) ?? ""
        TestRun.expect(claude.contains("marbles-hook"), "claude command")
        TestRun.expect(claude.contains("\"async\" : true") || claude.contains("\"async\": true"), "claude async")
        let cursor = (try? String(contentsOf: files.cursor, encoding: .utf8)) ?? ""
        TestRun.expect(!cursor.contains("failClosed"), "no failClosed")
    }

    private static func mergeIsIdempotent() {
        let files = tempFiles()
        try? Hooks.install(files: files)
        try? Hooks.install(files: files)
        let claude = try? JSONC.parseObject((try? String(contentsOf: files.claude)) ?? "")
        let hooks = claude?["hooks"] as? [String: Any]
        let start = hooks?["SessionStart"] as? [[String: Any]]
        let inner = start?.first?["hooks"] as? [[String: Any]] ?? []
        let owned = inner.filter { Hooks.isOwned(($0["command"] as? String) ?? "") }
        TestRun.expectEqual(owned.count, 1, "one owned SessionStart command")
    }

    private static func undoRemovesOnlyOurs() {
        let files = tempFiles()
        let starter = """
        {
          "hooks": {
            "SessionStart": [
              { "hooks": [{ "type": "command", "command": "echo hi" }] }
            ]
          }
        }
        """
        try? FileManager.default.createDirectory(at: files.claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? starter.write(to: files.claude, atomically: true, encoding: .utf8)
        try? Hooks.install(files: files)
        try? Hooks.undo(files: files)
        let text = (try? String(contentsOf: files.claude, encoding: .utf8)) ?? ""
        TestRun.expect(text.contains("echo hi"), "user hook remains")
        TestRun.expect(!text.contains("marbles-hook"), "ours removed")
    }

    private static func commentsSurvive() {
        let files = tempFiles()
        let starter = """
        {
          // keep-me
          "other": true
        }
        """
        try? FileManager.default.createDirectory(at: files.claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? starter.write(to: files.claude, atomically: true, encoding: .utf8)
        try? Hooks.install(files: files)
        let text = (try? String(contentsOf: files.claude, encoding: .utf8)) ?? ""
        TestRun.expect(text.contains("keep-me"), "comment survives")
        TestRun.expect(text.contains("marbles-hook"), "hooks added")
    }

    private static func invalidFileIsLeftAlone() {
        let files = tempFiles()
        try? FileManager.default.createDirectory(at: files.claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "not-json".write(to: files.claude, atomically: true, encoding: .utf8)
        do {
            try Hooks.install(files: files)
            TestRun.expect(false, "invalid claude should throw")
        } catch Hooks.HookError.invalidClaude {
            TestRun.expect(true, "invalid claude")
        } catch {
            TestRun.expect(false, "wrong error \(error)")
        }
        TestRun.expectEqual(try? String(contentsOf: files.claude, encoding: .utf8), "not-json", "invalid file untouched")
    }

    private static func cursorKeepsVersion() {
        let files = tempFiles()
        try? Hooks.install(files: files)
        let object = try? JSONC.parseObject((try? String(contentsOf: files.cursor)) ?? "")
        TestRun.expectEqual(object?["version"] as? Int, 1, "cursor version")
    }

    private static func tempFiles() -> Hooks.Files {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("marbles-hooks-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Hooks.Files(
            claude: root.appendingPathComponent("settings.json"),
            cursor: root.appendingPathComponent("hooks.json"),
            helper: URL(fileURLWithPath: "/tmp/Marbles.app/Contents/Helpers/marbles-hook")
        )
    }
}
