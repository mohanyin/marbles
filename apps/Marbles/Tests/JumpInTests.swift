import Foundation

enum JumpInTests {
    static func run() {
        visibilityBySource()
        demoDisables()
        injectedDisables()
        missingAppDisables()
        terminalNeedsCwd()
        claudeOpensChatURL()
        cursorOpensFolder()
        conductorActivates()
        prefersRunningTerminal()
    }

    private static func visibilityBySource() {
        let cli = Agent.make(id: "c", source: .cli)
        TestRun.expect(JumpRouter.isVisible(.claudeCode, agent: cli), "cli shows Claude")
        TestRun.expect(!JumpRouter.isVisible(.cursor, agent: cli), "cli hides Cursor")
        let cursor = Agent.make(id: "u", source: .cursor)
        TestRun.expect(!JumpRouter.isVisible(.claudeCode, agent: cursor), "cursor hides Claude")
        TestRun.expect(JumpRouter.isVisible(.cursor, agent: cursor), "cursor shows Cursor")
        let conductor = Agent.make(
            id: "w",
            source: .cli,
            cwd: URL(fileURLWithPath: "/Users/x/conductor/workspaces/app/ws"),
            conductorWorkspaceID: "ws"
        )
        TestRun.expect(JumpRouter.isVisible(.conductor, agent: conductor), "conductor cwd shows")
        TestRun.expect(!JumpRouter.isVisible(.conductor, agent: cli), "plain cli hides Conductor")
    }

    private static func demoDisables() {
        let demo = DemoMarble.make()
        let launcher = FakeLauncher(apps: [JumpRouter.claudeBundle, "com.apple.Terminal"])
        let claude = JumpRouter.decision(.claudeCode, agent: demo, launcher: launcher)
        TestRun.expect(claude.visible && !claude.enabled, "demo Claude is disabled")
        TestRun.expectEqual(claude.tooltip, Optional("Demo."))
        do {
            try JumpRouter.open(.claudeCode, agent: demo, launcher: launcher)
            TestRun.expect(false, "demo should throw")
        } catch JumpError.demo {
            TestRun.expect(launcher.opened.isEmpty && launcher.activated.isEmpty, "demo does not launch")
        } catch {
            TestRun.expect(false, "wrong error \(error)")
        }
    }

    private static func injectedDisables() {
        let injected = Agent.make(id: "debug-1", source: .cli, cwd: URL(fileURLWithPath: "/tmp"))
        let launcher = FakeLauncher(apps: [JumpRouter.claudeBundle, "com.apple.Terminal"])
        let terminal = JumpRouter.decision(.terminal, agent: injected, launcher: launcher)
        TestRun.expect(terminal.visible && !terminal.enabled, "injected Terminal is disabled")
        TestRun.expectEqual(terminal.tooltip, Optional("Demo."))
    }

    private static func missingAppDisables() {
        let agent = Agent.make(id: "a", source: .cli)
        let launcher = FakeLauncher(apps: [])
        let claude = JumpRouter.decision(.claudeCode, agent: agent, launcher: launcher)
        TestRun.expect(claude.visible && !claude.enabled, "missing Claude disables")
        TestRun.expectEqual(claude.tooltip, Optional("Claude Code isn’t installed"))
        let cursorAgent = Agent.make(id: "u", source: .cursor)
        let cursor = JumpRouter.decision(.cursor, agent: cursorAgent, launcher: launcher)
        TestRun.expectEqual(cursor.tooltip, Optional("Cursor isn’t installed"))
    }

    private static func terminalNeedsCwd() {
        let agent = Agent.make(id: "t", source: .cli)
        let launcher = FakeLauncher(apps: ["com.apple.Terminal"])
        let decision = JumpRouter.decision(.terminal, agent: agent, launcher: launcher)
        TestRun.expect(decision.visible && !decision.enabled, "no cwd disables Terminal")
        TestRun.expectEqual(decision.tooltip, Optional("No working directory"))
        let withCwd = Agent.make(id: "t", source: .cli, cwd: URL(fileURLWithPath: "/tmp"))
        TestRun.expect(
            JumpRouter.decision(.terminal, agent: withCwd, launcher: launcher).enabled,
            "cwd enables Terminal"
        )
    }

    private static func claudeOpensChatURL() {
        let agent = Agent.make(id: "1bea041f-5023-4d56-a3f3-32cf28f1e580", source: .claudeApp)
        let launcher = FakeLauncher(apps: [JumpRouter.claudeBundle])
        do {
            try JumpRouter.open(.claudeCode, agent: agent, launcher: launcher)
        } catch {
            TestRun.expect(false, "claude open threw \(error)")
        }
        TestRun.expectEqual(
            launcher.opened.first?.absoluteString,
            Optional("claude://claude.ai/chat/1bea041f-5023-4d56-a3f3-32cf28f1e580")
        )
        TestRun.expectEqual(launcher.activated.first, Optional(JumpRouter.claudeBundle))
        TestRun.expect(
            !launcher.opened.contains { $0.absoluteString.contains("code/new") },
            "must not start a new session"
        )
    }

    private static func cursorOpensFolder() {
        let agent = Agent.make(id: "conv", source: .cursor, cwd: URL(fileURLWithPath: "/tmp/proj"))
        let launcher = FakeLauncher(apps: ["com.todesktop.230313mzl4w4u92"])
        do {
            try JumpRouter.open(.cursor, agent: agent, launcher: launcher)
        } catch {
            TestRun.expect(false, "cursor open threw \(error)")
        }
        TestRun.expectEqual(launcher.folders.first?.1, Optional("com.todesktop.230313mzl4w4u92"))
        TestRun.expectEqual(launcher.folders.first?.0.path, Optional("/tmp/proj"))
    }

    private static func conductorActivates() {
        let agent = Agent.make(
            id: "cd",
            source: .conductor,
            cwd: URL(fileURLWithPath: "/Users/x/conductor/workspaces/app/ws"),
            conductorWorkspaceID: "ws"
        )
        let launcher = FakeLauncher(apps: [JumpRouter.conductorBundle])
        do {
            try JumpRouter.open(.conductor, agent: agent, launcher: launcher)
        } catch {
            TestRun.expect(false, "conductor open threw \(error)")
        }
        TestRun.expectEqual(launcher.activated.first, Optional(JumpRouter.conductorBundle))
    }

    private static func prefersRunningTerminal() {
        let agent = Agent.make(id: "t", source: .cli, cwd: URL(fileURLWithPath: "/tmp"))
        let launcher = FakeLauncher(
            apps: ["com.googlecode.iterm2", "com.apple.Terminal"],
            running: ["com.googlecode.iterm2"]
        )
        do {
            try JumpRouter.open(.terminal, agent: agent, launcher: launcher)
        } catch {
            TestRun.expect(false, "terminal open threw \(error)")
        }
        TestRun.expectEqual(launcher.folders.first?.1, Optional("com.googlecode.iterm2"))
    }
}

final class FakeLauncher: AppLaunching {
    var apps: Set<String>
    var running: Set<String>
    var opened: [URL] = []
    var activated: [String] = []
    var folders: [(URL, String)] = []

    init(apps: Set<String>, running: Set<String> = []) {
        self.apps = apps
        self.running = running
    }

    func applicationExists(bundleID: String) -> Bool { apps.contains(bundleID) }
    func runningBundleIDs() -> Set<String> { running }

    func open(_ url: URL) throws {
        opened.append(url)
    }

    func openApplication(bundleID: String) throws {
        guard apps.contains(bundleID) else { throw JumpError.appMissing }
        activated.append(bundleID)
    }

    func open(_ folder: URL, bundleID: String) throws {
        guard apps.contains(bundleID) else { throw JumpError.appMissing }
        folders.append((folder, bundleID))
    }
}
