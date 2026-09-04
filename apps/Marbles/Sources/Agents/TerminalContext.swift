import Foundation

/// Where a session's process lives: its controlling tty, the app at the top of its process
/// tree, and the multiplexer / emulator identifiers its environment carries. Captured by
/// `marbles-hook` (which runs inside the session's process tree) and posted alongside the
/// hook payload under `marbles_client`. Jump-in uses it to bring the right tab forward.
struct TerminalContext: Equatable {
    /// One link in the parent chain, nearest first. `name` is the kernel's 16-char comm.
    struct Ancestor: Equatable {
        var pid: Int32
        var name: String
    }

    /// Controlling terminal, e.g. `/dev/ttys004`.
    var tty: String?
    /// The ancestor whose parent is launchd: the terminal emulator, IDE, or tmux server.
    var terminalPID: Int32?
    var terminalPath: String?
    /// Parent chain from the hook's parent up to (and including) the launchd child.
    var ancestors: [Ancestor]
    var termProgram: String?
    var termProgramVersion: String?
    /// Terminal.app and iTerm2 both set `TERM_SESSION_ID`.
    var termSessionID: String?
    var itermSessionID: String?
    var kittyWindowID: String?
    var kittyListenOn: String?
    var weztermPane: String?
    /// `$TMUX` — socket path, client pid, and session index separated by commas.
    var tmux: String?
    var tmuxPane: String?

    static let payloadKey = "marbles_client"

    /// Nearest ancestor that is the agent CLI itself, when we can tell. The native Claude Code
    /// binary is installed under its version number (`~/.local/share/claude/versions/2.1.260`),
    /// so the kernel's comm for it reads like `2.1.260`.
    var agentPID: Int32? {
        ancestors.first { link in
            ["claude", "node", "cursor-agent"].contains(link.name) || Self.looksLikeVersion(link.name)
        }?.pid
    }

    private static func looksLikeVersion(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    var isInsideTmux: Bool {
        tmuxPane != nil && tmux != nil
    }

    /// Socket path from `$TMUX`, so a non-default `-L`/`-S` server still resolves.
    var tmuxSocket: String? {
        tmux?.split(separator: ",").first.map(String.init)
    }

    // MARK: JSON

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = [:]
        object["tty"] = tty
        object["terminal_pid"] = terminalPID.map { Int($0) }
        object["terminal_path"] = terminalPath
        if !ancestors.isEmpty {
            object["ancestors"] = ancestors.map { ["pid": Int($0.pid), "name": $0.name] }
        }
        object["term_program"] = termProgram
        object["term_program_version"] = termProgramVersion
        object["term_session_id"] = termSessionID
        object["iterm_session_id"] = itermSessionID
        object["kitty_window_id"] = kittyWindowID
        object["kitty_listen_on"] = kittyListenOn
        object["wezterm_pane"] = weztermPane
        object["tmux"] = tmux
        object["tmux_pane"] = tmuxPane
        return object
    }

    init(
        tty: String? = nil,
        terminalPID: Int32? = nil,
        terminalPath: String? = nil,
        ancestors: [Ancestor] = [],
        termProgram: String? = nil,
        termProgramVersion: String? = nil,
        termSessionID: String? = nil,
        itermSessionID: String? = nil,
        kittyWindowID: String? = nil,
        kittyListenOn: String? = nil,
        weztermPane: String? = nil,
        tmux: String? = nil,
        tmuxPane: String? = nil
    ) {
        self.tty = tty
        self.terminalPID = terminalPID
        self.terminalPath = terminalPath
        self.ancestors = ancestors
        self.termProgram = termProgram
        self.termProgramVersion = termProgramVersion
        self.termSessionID = termSessionID
        self.itermSessionID = itermSessionID
        self.kittyWindowID = kittyWindowID
        self.kittyListenOn = kittyListenOn
        self.weztermPane = weztermPane
        self.tmux = tmux
        self.tmuxPane = tmuxPane
    }

    init?(jsonObject: Any?) {
        guard let obj = jsonObject as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            guard let value = obj[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        func int32(_ key: String) -> Int32? {
            if let value = obj[key] as? Int { return Int32(clamping: value) }
            if let value = obj[key] as? Double { return Int32(clamping: Int(value)) }
            if let value = obj[key] as? String { return Int32(value) }
            return nil
        }
        tty = text("tty")
        terminalPID = int32("terminal_pid")
        terminalPath = text("terminal_path")
        ancestors = (obj["ancestors"] as? [[String: Any]] ?? []).compactMap { link in
            guard let pid = (link["pid"] as? Int).map(Int32.init(clamping:)) else { return nil }
            return Ancestor(pid: pid, name: link["name"] as? String ?? "")
        }
        termProgram = text("term_program")
        termProgramVersion = text("term_program_version")
        termSessionID = text("term_session_id")
        itermSessionID = text("iterm_session_id")
        kittyWindowID = text("kitty_window_id")
        kittyListenOn = text("kitty_listen_on")
        weztermPane = text("wezterm_pane")
        tmux = text("tmux")
        tmuxPane = text("tmux_pane")
        if tty == nil, terminalPID == nil, ancestors.isEmpty, termProgram == nil, tmuxPane == nil {
            return nil
        }
    }

    // MARK: Capture

    /// Read the calling process's own ancestry and environment. Cheap: a handful of sysctls.
    static func capture(environment: [String: String] = ProcessInfo.processInfo.environment) -> TerminalContext {
        var context = TerminalContext()
        context.ancestors = ProcessTree.ancestors(of: getpid())
        context.tty = ProcessTree.tty(of: getpid())
            ?? context.ancestors.lazy.compactMap { ProcessTree.tty(of: $0.pid) }.first
        if let top = context.ancestors.last {
            context.terminalPID = top.pid
            context.terminalPath = ProcessTree.path(of: top.pid)
        }
        context.termProgram = environment["TERM_PROGRAM"]
        context.termProgramVersion = environment["TERM_PROGRAM_VERSION"]
        context.termSessionID = environment["TERM_SESSION_ID"]
        context.itermSessionID = environment["ITERM_SESSION_ID"]
        context.kittyWindowID = environment["KITTY_WINDOW_ID"]
        context.kittyListenOn = environment["KITTY_LISTEN_ON"]
        context.weztermPane = environment["WEZTERM_PANE"]
        context.tmux = environment["TMUX"]
        context.tmuxPane = environment["TMUX_PANE"]
        return context
    }
}

/// Thin sysctl wrappers. No AppKit so the hook helper can link them.
enum ProcessTree {
    struct Info {
        var pid: Int32
        var parentPID: Int32
        var name: String
        var ttyDevice: UInt32
    }

    static func info(of pid: Int32) -> Info? {
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafePointer(to: &proc.kp_proc.p_comm) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
        return Info(
            pid: proc.kp_proc.p_pid,
            parentPID: proc.kp_eproc.e_ppid,
            name: name,
            ttyDevice: UInt32(bitPattern: proc.kp_eproc.e_tdev)
        )
    }

    /// Parents of `pid`, nearest first, stopping at the launchd child. Bounded so a cycle or a
    /// reparented orphan can't spin.
    static func ancestors(of pid: Int32) -> [TerminalContext.Ancestor] {
        var chain: [TerminalContext.Ancestor] = []
        var current = pid
        for _ in 0..<32 {
            guard let info = info(of: current), info.parentPID > 1 else { break }
            guard let parent = self.info(of: info.parentPID) else { break }
            chain.append(.init(pid: parent.pid, name: parent.name))
            current = parent.pid
        }
        return chain
    }

    /// `/dev/ttysNNN` for a process, or nil when it has no controlling terminal.
    static func tty(of pid: Int32) -> String? {
        guard let info = info(of: pid), info.ttyDevice != UInt32.max, info.ttyDevice != 0 else { return nil }
        guard let name = devname(dev_t(info.ttyDevice), mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: name)
    }

    static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
