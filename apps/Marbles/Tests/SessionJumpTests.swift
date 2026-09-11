import Foundation

enum SessionJumpTests {
    static func run() {
        ghosttyPrefersTitleHintInSameDirectory()
        ghosttySkipsIdleShellsInSameDirectory()
        ghosttyUniqueTitleHitWithoutDirectoryMatch()
        ghosttyGivesUpWhenAmbiguous()
        parsesListing()
        normalizesPaths()
        plansByHostBundle()
        plansTmux()
        plansFallbacks()
        capturesOwnAncestry()
        capturesAnotherProcess()
        discoveredSessionsKeepTheirPane()
        roundTripsJSON()
    }

    private static let repo = "/Users/mikaela/Repositories/website"

    private static func terminal(_ id: String, _ title: String, _ cwd: String) -> GhosttyTerminal {
        GhosttyTerminal(windowID: "w1", tabID: "tab-\(id)", terminalID: id, title: title, workingDirectory: cwd)
    }

    private static func ghosttyPrefersTitleHintInSameDirectory() {
        let terminals = [
            terminal("a", "mikaela@Alioth:~/Repositories/website", repo),
            terminal("b", "✳ Colored borders", repo),
            terminal("c", "◑ install.sh", "/Users/mikaela/Repositories/marbles"),
            terminal("d", "✳ Fix login", repo),
        ]
        let hit = SessionJump.chooseGhosttyTerminal(terminals, cwd: repo, titleHint: "Fix login")
        TestRun.expectEqual(hit?.terminalID, "d", "AI title wins among same-directory tabs")
        let insensitive = SessionJump.chooseGhosttyTerminal(terminals, cwd: repo, titleHint: "colored BORDERS")
        TestRun.expectEqual(insensitive?.terminalID, "b", "title match ignores case")
    }

    private static func ghosttySkipsIdleShellsInSameDirectory() {
        let terminals = [
            terminal("a", "mikaela@Alioth:~/Repositories/website", repo),
            terminal("b", "✳ Colored borders", repo),
        ]
        let hit = SessionJump.chooseGhosttyTerminal(terminals, cwd: repo + "/", titleHint: nil)
        TestRun.expectEqual(hit?.terminalID, "b", "a Claude tab beats a bare prompt; trailing slash ignored")
        let onlyShell = SessionJump.chooseGhosttyTerminal([terminals[0]], cwd: repo, titleHint: "nope")
        TestRun.expectEqual(onlyShell?.terminalID, "a", "lone same-directory tab still wins")
    }

    private static func ghosttyUniqueTitleHitWithoutDirectoryMatch() {
        let terminals = [
            terminal("a", "✳ Colored borders", repo),
            terminal("b", "◑ install.sh", "/Users/mikaela/Repositories/marbles"),
        ]
        let hit = SessionJump.chooseGhosttyTerminal(terminals, cwd: "/elsewhere", titleHint: "install.sh")
        TestRun.expectEqual(hit?.terminalID, "b", "unique title hit rescues a moved session")
    }

    private static func ghosttyGivesUpWhenAmbiguous() {
        let terminals = [
            terminal("a", "✳ Fix login", repo),
            terminal("b", "✳ Fix login", "/other"),
        ]
        TestRun.expect(
            SessionJump.chooseGhosttyTerminal(terminals, cwd: "/elsewhere", titleHint: "Fix login") == nil,
            "two title hits and no directory match → nil"
        )
        TestRun.expect(
            SessionJump.chooseGhosttyTerminal(terminals, cwd: nil, titleHint: nil) == nil,
            "nothing to match on → nil"
        )
    }

    private static func parsesListing() {
        let fs = "\u{1F}", rs = "\u{1E}"
        let text = "w1\(fs)t1\(fs)s1\(fs)✳ Title\(fs)\(repo)\n\(rs)w1\(fs)t2\(fs)s2\(fs)\(fs)\(rs)"
        let parsed = SessionJump.parseGhosttyListing(text)
        TestRun.expectEqual(parsed.count, 2)
        TestRun.expectEqual(parsed.first?.title, "✳ Title")
        TestRun.expectEqual(parsed.first?.workingDirectory, repo, "trailing newline from osascript trimmed")
        TestRun.expectEqual(parsed.last?.workingDirectory, "", "empty fields survive")
        TestRun.expect(SessionJump.parseGhosttyListing("").isEmpty, "empty listing")
    }

    private static func normalizesPaths() {
        TestRun.expectEqual(SessionJump.normalizePath("file:///Users/x/y/"), "/Users/x/y")
        TestRun.expectEqual(SessionJump.normalizePath("/Users/x//y/./z/../"), "/Users/x/y")
        TestRun.expect(SessionJump.looksLikeShellPrompt("mikaela@Alioth-BXQ6:~/Repositories/website"), "prompt title")
        TestRun.expect(!SessionJump.looksLikeShellPrompt("✳ Email me at a@b: now"), "prose with @ is not a prompt")
        TestRun.expect(!SessionJump.looksLikeShellPrompt("◑ install.sh"), "Claude title")
    }

    private static func agent(source: Source = .cli, cwd: String? = repo, terminal: TerminalContext?) -> Agent {
        var agent = Agent.make(id: "s1", source: source, cwd: cwd.map { URL(fileURLWithPath: $0) })
        agent.terminal = terminal
        return agent
    }

    private static func plansByHostBundle() {
        let context = TerminalContext(tty: "/dev/ttys004", terminalPID: 752, terminalPath: "/Applications/Ghostty.app/Contents/MacOS/ghostty", ancestors: [.init(pid: 1056, name: "zsh"), .init(pid: 752, name: "ghostty")])
        let ghostty = SessionJump.plan(for: agent(terminal: context), titleHint: "install.sh", host: HostApp(pid: 752, bundleID: HostBundle.ghostty, isTmuxServer: false))
        TestRun.expectEqual(ghostty, JumpPlan(tmux: nil, target: .ghostty(pid: 752, cwd: repo, titleHint: "install.sh")))

        let terminalApp = SessionJump.plan(for: agent(terminal: context), titleHint: nil, host: HostApp(pid: 9, bundleID: HostBundle.appleTerminal, isTmuxServer: false))
        TestRun.expectEqual(terminalApp.target, .appleTerminal(pid: 9, tty: "/dev/ttys004"))

        let iterm = SessionJump.plan(for: agent(terminal: context), titleHint: nil, host: HostApp(pid: 9, bundleID: HostBundle.iterm, isTmuxServer: false))
        TestRun.expectEqual(iterm.target, .iterm(pid: 9, tty: "/dev/ttys004"))

        let other = SessionJump.plan(for: agent(terminal: context), titleHint: nil, host: HostApp(pid: 9, bundleID: "com.microsoft.VSCode", isTmuxServer: false))
        TestRun.expectEqual(other.target, .activate(pid: 9), "unknown hosts are simply activated")

        var kittyContext = context
        kittyContext.kittyWindowID = "3"
        kittyContext.kittyListenOn = "unix:/tmp/k"
        let kitty = SessionJump.plan(for: agent(terminal: kittyContext), titleHint: nil, host: HostApp(pid: 9, bundleID: HostBundle.kitty, isTmuxServer: false))
        TestRun.expectEqual(kitty.target, .kitty(pid: 9, windowID: "3", listenOn: "unix:/tmp/k"))
    }

    private static func plansTmux() {
        var context = TerminalContext(tty: "/dev/ttys007", terminalPID: 400, terminalPath: "/opt/homebrew/bin/tmux", ancestors: [.init(pid: 401, name: "zsh"), .init(pid: 400, name: "tmux")])
        context.tmux = "/private/tmp/tmux-501/default,400,0"
        context.tmuxPane = "%5"
        let plan = SessionJump.plan(for: agent(terminal: context), titleHint: nil, host: HostApp(pid: 400, bundleID: nil, isTmuxServer: true))
        TestRun.expectEqual(plan.tmux, TmuxHop(socket: "/private/tmp/tmux-501/default", pane: "%5"))
        TestRun.expectEqual(plan.target, .tmuxClient(socket: "/private/tmp/tmux-501/default", pane: "%5"))

        // tmux server gone but the pane env is still known: still worth asking tmux.
        let orphan = SessionJump.plan(for: agent(terminal: context), titleHint: nil, host: nil)
        TestRun.expectEqual(orphan.target, .tmuxClient(socket: "/private/tmp/tmux-501/default", pane: "%5"))

        // tmux inside Ghostty: hop the pane, then pick the Ghostty tab.
        let hosted = SessionJump.plan(for: agent(terminal: context), titleHint: nil, host: HostApp(pid: 752, bundleID: HostBundle.ghostty, isTmuxServer: false))
        TestRun.expectEqual(hosted.tmux?.pane, "%5")
        TestRun.expectEqual(hosted.target, .ghostty(pid: 752, cwd: repo, titleHint: nil))
    }

    private static func plansFallbacks() {
        TestRun.expectEqual(SessionJump.plan(for: agent(terminal: nil), titleHint: nil, host: nil).target, .openTerminal(cwd: repo), "no context → Terminal at cwd")
        TestRun.expectEqual(SessionJump.plan(for: agent(cwd: nil, terminal: nil), titleHint: nil, host: nil).target, .none, "no context, no cwd → nothing")
        TestRun.expectEqual(SessionJump.plan(for: agent(source: .cursor, terminal: nil), titleHint: nil, host: nil).target, .activateBundle(HostBundle.cursor))
        TestRun.expectEqual(SessionJump.plan(for: agent(source: .conductor, terminal: nil), titleHint: nil, host: nil).target, .activateBundle(HostBundle.conductor))
        TestRun.expectEqual(SessionJump.plan(for: agent(source: .claudeApp, terminal: nil), titleHint: nil, host: nil).target, .activateBundle(HostBundle.claudeApp))

        var demo = Agent.debugDummy(index: 0)
        demo.terminal = TerminalContext(terminalPID: 752)
        TestRun.expectEqual(SessionJump.plan(for: demo, titleHint: nil, host: HostApp(pid: 752, bundleID: HostBundle.ghostty, isTmuxServer: false)).target, .none, "placeholders never jump")
    }

    private static func capturesOwnAncestry() {
        let context = TerminalContext.capture(environment: ["TERM_PROGRAM": "ghostty", "TMUX_PANE": "%1", "TMUX": "/tmp/s,1,0"])
        TestRun.expect(!context.ancestors.isEmpty, "test runner has a parent")
        TestRun.expect(context.terminalPID != nil, "top of tree resolved")
        TestRun.expectEqual(context.ancestors.last?.pid, context.terminalPID)
        TestRun.expectEqual(context.termProgram, "ghostty")
        TestRun.expect(context.isInsideTmux, "tmux env read")
        TestRun.expectEqual(context.tmuxSocket, "/tmp/s")
        TestRun.expect(ProcessTree.path(of: getpid())?.hasSuffix("marbles-tests") == true, "own path resolves")
        TestRun.expect(ProcessTree.info(of: 1)?.name == "launchd", "pid 1 is launchd")
    }

    private static func roundTripsJSON() {
        var context = TerminalContext(tty: "/dev/ttys004", terminalPID: 752, terminalPath: "/Applications/Ghostty.app/Contents/MacOS/ghostty", ancestors: [.init(pid: 1056, name: "zsh"), .init(pid: 752, name: "ghostty")])
        context.termProgram = "ghostty"
        context.termProgramVersion = "1.3.1"
        context.tmux = "/tmp/s,1,0"
        context.tmuxPane = "%2"
        let data = try? JSONSerialization.data(withJSONObject: context.jsonObject())
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        TestRun.expectEqual(TerminalContext(jsonObject: object), context)
        TestRun.expect(TerminalContext(jsonObject: [String: Any]()) == nil, "empty object → nil")
        TestRun.expect(TerminalContext(jsonObject: "junk") == nil, "non-object → nil")
        TestRun.expectEqual(context.agentPID, nil, "no claude in chain")
        context.ancestors.insert(.init(pid: 6855, name: "claude"), at: 0)
        TestRun.expectEqual(context.agentPID, 6855)
        context.ancestors[0].name = "2.1.260"
        TestRun.expectEqual(context.agentPID, 6855, "native binary named by version")
        context.ancestors[0].name = "login"
        TestRun.expectEqual(context.agentPID, nil)
    }

    /// Discovery has only a pid, so the terminal context is rebuilt from that process's
    /// environment rather than the hook payload. Reading the *caller's* ancestry instead would
    /// describe Marbles' own terminal, so the pid has to be honoured.
    private static func capturesAnotherProcess() {
        let own = TerminalContext.capture(environment: [:])
        let launchd = TerminalContext.capture(environment: [:], pid: 1)
        TestRun.expect(
            own.ancestors.map(\.pid) != launchd.ancestors.map(\.pid),
            "capture(pid:) reads the named process, not the caller"
        )
        let env = TerminalContext.capture(environment: ["TMUX_PANE": "%7", "TERM_PROGRAM": "tmux"], pid: 1)
        TestRun.expectEqual(env.tmuxPane, "%7", "markers come from the supplied environment")
        TestRun.expect(env.isInsideTmux == false, "TMUX_PANE alone is not a tmux session")

        // The path discovery actually takes: read a real process's environment by pid. Our own
        // pid is the one process guaranteed to be running, and it always has some environment.
        let live = ProcessTree.environment(of: ProcessInfo.processInfo.processIdentifier)
        TestRun.expect(!live.isEmpty, "a live process's environment is readable by pid")
        TestRun.expect(live["PATH"] != nil, "and carries real variables, not just keys")
    }

    /// The regression that made every discovered marble open a new window: with a terminal
    /// context the plan must hop to the real pane, and a Conductor session must activate
    /// Conductor rather than fall through to the terminal fallback.
    private static func discoveredSessionsKeepTheirPane() {
        let inTmux = TerminalContext.capture(
            environment: ["TMUX": "/private/tmp/tmux-501/default,123,0", "TMUX_PANE": "%36"],
            pid: 1
        )
        let discovered = SessionJump.plan(
            for: agent(source: .discovery, terminal: inTmux),
            titleHint: nil,
            host: nil
        )
        TestRun.expectEqual(discovered.tmux?.pane, "%36", "the discovered session's pane is carried")
        TestRun.expectEqual(
            discovered.target,
            .tmuxClient(socket: "/private/tmp/tmux-501/default", pane: "%36"),
            "a discovered tmux session attaches its pane instead of opening a terminal"
        )

        let conductor = SessionJump.plan(
            for: agent(source: .conductor, cwd: "/Users/mikaela/conductor/workspaces/website/yangon", terminal: nil),
            titleHint: nil,
            host: nil
        )
        TestRun.expectEqual(
            conductor.target,
            .activateBundle(HostBundle.conductor),
            "a Conductor session activates Conductor, not a terminal"
        )
    }
}
