import AppKit

/// Carries out a `JumpPlan`: activates the host app right away for instant feedback, then
/// selects the exact tab / pane off the main thread (AppleScript and CLI round-trips can block
/// on a first-run Automation prompt).
@MainActor
final class SessionJumpRunner {
    static let shared = SessionJumpRunner()

    private let queue = DispatchQueue(label: "dev.marbles.jump", qos: .userInitiated)

    func jump(to agent: Agent) {
        let host = resolveHost(agent.terminal)
        let hint = TranscriptPeek.latestAITitle(path: agent.transcriptPath)
        let plan = SessionJump.plan(for: agent, titleHint: hint, host: host)
        perform(plan)
    }

    func perform(_ plan: JumpPlan) {
        switch plan.target {
        case .none:
            return
        case .ghostty(let pid, let cwd, let hint):
            activate(pid: pid)
            queue.async { [tmux = plan.tmux] in
                Self.selectTmux(tmux)
                Self.focusGhostty(cwd: cwd, titleHint: hint)
            }
        case .appleTerminal(let pid, let tty):
            activate(pid: pid)
            queue.async { [tmux = plan.tmux] in
                Self.selectTmux(tmux)
                if let tty { Self.focusAppleTerminal(tty: tty) }
            }
        case .iterm(let pid, let tty):
            activate(pid: pid)
            queue.async { [tmux = plan.tmux] in
                Self.selectTmux(tmux)
                if let tty { Self.focusITerm(tty: tty) }
            }
        case .kitty(let pid, let windowID, let listenOn):
            let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL
            activate(pid: pid)
            queue.async { [tmux = plan.tmux] in
                Self.selectTmux(tmux)
                if let windowID, let listenOn, let bundleURL {
                    let kitten = bundleURL.appendingPathComponent("Contents/MacOS/kitten").path
                    _ = Self.run(kitten, ["@", "--to", listenOn, "focus-window", "--match", "id:\(windowID)"])
                }
            }
        case .wezterm(let pid, let pane):
            let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL
            activate(pid: pid)
            queue.async { [tmux = plan.tmux] in
                Self.selectTmux(tmux)
                if let pane, let bundleURL {
                    let wezterm = bundleURL.appendingPathComponent("Contents/MacOS/wezterm").path
                    _ = Self.run(wezterm, ["cli", "activate-pane", "--pane-id", pane])
                }
            }
        case .tmuxClient(let socket, let pane):
            queue.async { [tmux = plan.tmux] in
                Self.selectTmux(tmux)
                guard let clientPID = Self.tmuxClientPID(socket: socket, pane: pane) else { return }
                let top = ProcessTree.ancestors(of: clientPID).last?.pid ?? clientPID
                Task { @MainActor in self.activate(pid: top) }
            }
        case .activate(let pid):
            activate(pid: pid)
            queue.async { [tmux = plan.tmux] in Self.selectTmux(tmux) }
        case .activateBundle(let bundleID):
            activate(bundleID: bundleID)
        case .openTerminal(let cwd):
            openTerminal(at: cwd)
        }
    }

    // MARK: Host resolution

    /// The app at the top of the captured process tree, or the same app relaunched (Ghostty
    /// quit and reopened keeps the session's tty only if the tab survived, so prefer the live pid).
    func resolveHost(_ terminal: TerminalContext?) -> HostApp? {
        guard let terminal, let pid = terminal.terminalPID else { return nil }
        let topName = terminal.ancestors.last?.name ?? ""
        let isTmux = topName == "tmux" || (terminal.terminalPath ?? "").hasSuffix("/tmux")
        if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return HostApp(pid: pid, bundleID: app.bundleIdentifier ?? bundleID(fromPath: terminal.terminalPath), isTmuxServer: isTmux)
        }
        if isTmux { return HostApp(pid: pid, bundleID: nil, isTmuxServer: true) }
        guard let bundleID = bundleID(fromPath: terminal.terminalPath),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        return HostApp(pid: app.processIdentifier, bundleID: bundleID, isTmuxServer: false)
    }

    private func bundleID(fromPath path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return Bundle(path: String(path[..<range.upperBound]))?.bundleIdentifier
    }

    // MARK: Activation

    private func activate(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.activate(from: .current, options: [.activateAllWindows]) { return }
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    private func activate(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            activate(pid: app.processIdentifier)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func openTerminal(at cwd: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: HostBundle.appleTerminal) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: cwd, isDirectory: true)], withApplicationAt: terminal, configuration: configuration)
    }

    // MARK: Ghostty

    nonisolated private static func focusGhostty(cwd: String?, titleHint: String?) {
        let listing = """
        tell application "Ghostty"
          set fs to character id 31
          set rs to character id 30
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in terminals of t
                set ttl to ""
                set wd to ""
                try
                  set ttl to name of s
                end try
                try
                  set wd to working directory of s
                end try
                set out to out & (id of w) & fs & (id of t) & fs & (id of s) & fs & ttl & fs & wd & rs
              end repeat
            end repeat
          end repeat
          return out
        end tell
        """
        guard let text = runAppleScript(listing) else { return }
        let terminals = SessionJump.parseGhosttyListing(text)
        guard let hit = SessionJump.chooseGhosttyTerminal(terminals, cwd: cwd, titleHint: titleHint) else { return }
        let focus = """
        tell application "Ghostty"
          try
            activate window (window id \(quoted(hit.windowID)))
          end try
          try
            select tab (tab id \(quoted(hit.tabID)) of window id \(quoted(hit.windowID)))
          end try
          try
            focus (terminal id \(quoted(hit.terminalID)))
          end try
        end tell
        """
        _ = runAppleScript(focus)
    }

    // MARK: Terminal.app / iTerm2

    nonisolated private static func focusAppleTerminal(tty: String) {
        let script = """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is \(quoted(tty)) then
                set selected tab of w to t
                set index of w to 1
                return true
              end if
            end repeat
          end repeat
          return false
        end tell
        """
        _ = runAppleScript(script)
    }

    nonisolated private static func focusITerm(tty: String) {
        let script = """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is \(quoted(tty)) then
                  select s
                  select t
                  select w
                  return true
                end if
              end repeat
            end repeat
          end repeat
          return false
        end tell
        """
        _ = runAppleScript(script)
    }

    // MARK: tmux

    nonisolated private static func selectTmux(_ hop: TmuxHop?) {
        guard let hop, let tmux = tmuxBinary() else { return }
        let base = hop.socket.map { ["-S", $0] } ?? []
        _ = run(tmux, base + ["switch-client", "-t", hop.pane])
        _ = run(tmux, base + ["select-window", "-t", hop.pane])
        _ = run(tmux, base + ["select-pane", "-t", hop.pane])
    }

    nonisolated private static func tmuxClientPID(socket: String?, pane: String?) -> Int32? {
        guard let tmux = tmuxBinary() else { return nil }
        let base = socket.map { ["-S", $0] } ?? []
        var args = base + ["list-clients", "-F", "#{client_pid}"]
        if let pane { args += ["-t", pane] }
        let output = run(tmux, args) ?? run(tmux, base + ["list-clients", "-F", "#{client_pid}"])
        return output?.split(whereSeparator: \.isNewline).compactMap { Int32($0) }.first
    }

    nonisolated private static func tmuxBinary() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Subprocesses

    nonisolated private static func runAppleScript(_ source: String) -> String? {
        run("/usr/bin/osascript", ["-e", source], timeout: 8)
    }

    /// Run a helper and return trimmed stdout, or nil on non-zero exit, launch failure, or timeout.
    nonisolated private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 4) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain stdout concurrently so a chatty child can't fill the pipe and never exit.
        let output = OutputBox()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            output.data = stdout.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        drained.wait()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    nonisolated private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
