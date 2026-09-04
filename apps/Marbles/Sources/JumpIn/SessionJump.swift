import Foundation

/// Bundle identifiers of the apps a session can live in.
enum HostBundle {
    static let ghostty = "com.mitchellh.ghostty"
    static let appleTerminal = "com.apple.Terminal"
    static let iterm = "com.googlecode.iterm2"
    static let kitty = "net.kovidgoyal.kitty"
    static let wezterm = "com.github.wez.wezterm"
    static let cursor = "com.todesktop.230313mzl4w4u92"
    static let claudeApp = "com.anthropic.claude-code"
    static let conductor = "com.conductor.app"
    /// Older Conductor builds shipped under this identifier.
    static let conductorLegacy = "build.conductor.desktop"
}

/// The running process at the top of a session's tree, resolved by the runner (it needs AppKit
/// to map a pid to a bundle). `isTmuxServer` means the tree ends at tmux, not at a window.
struct HostApp: Equatable {
    var pid: Int32
    var bundleID: String?
    var isTmuxServer: Bool
}

/// A tmux pane to select before the terminal comes forward.
struct TmuxHop: Equatable {
    var socket: String?
    var pane: String
}

/// What clicking a marble does to bring its session forward.
enum JumpTarget: Equatable {
    /// Ghostty exposes each terminal's cwd and title over AppleScript, but not its tty.
    case ghostty(pid: Int32, cwd: String?, titleHint: String?)
    /// Terminal.app tabs carry their tty, so this is exact.
    case appleTerminal(pid: Int32, tty: String?)
    /// iTerm2 sessions carry their tty, so this is exact.
    case iterm(pid: Int32, tty: String?)
    case kitty(pid: Int32, windowID: String?, listenOn: String?)
    case wezterm(pid: Int32, pane: String?)
    /// The tree ends at a tmux server; ask it which client is attached and surface that.
    case tmuxClient(socket: String?, pane: String?)
    /// Any other host: VS Code, Warp, the Claude app… bring the app forward.
    case activate(pid: Int32)
    case activateBundle(String)
    /// Nothing told us where the session lives: open a fresh Terminal in its directory.
    case openTerminal(cwd: String)
    case none
}

struct JumpPlan: Equatable {
    var tmux: TmuxHop?
    var target: JumpTarget
}

/// One Ghostty terminal surface as reported by its AppleScript dictionary.
struct GhosttyTerminal: Equatable {
    var windowID: String
    var tabID: String
    var terminalID: String
    var title: String
    var workingDirectory: String
}

enum SessionJump {
    /// Pure. `host` is the resolved top-of-tree app (nil when it has quit or was never captured);
    /// `titleHint` is the transcript's AI title, which Claude Code also paints into the tab title.
    static func plan(for agent: Agent, titleHint: String?, host: HostApp?) -> JumpPlan {
        if agent.isInjected || agent.isDemo { return JumpPlan(tmux: nil, target: .none) }
        var plan = JumpPlan(tmux: nil, target: .none)
        let cwd = agent.cwd?.path

        if let terminal = agent.terminal {
            if terminal.isInsideTmux, let pane = terminal.tmuxPane {
                plan.tmux = TmuxHop(socket: terminal.tmuxSocket, pane: pane)
            }
            if let host {
                plan.target = target(for: host, terminal: terminal, cwd: cwd, titleHint: titleHint)
                return plan
            }
            if terminal.isInsideTmux {
                plan.target = .tmuxClient(socket: terminal.tmuxSocket, pane: terminal.tmuxPane)
                return plan
            }
        }

        switch agent.source {
        case .cursor:
            plan.target = .activateBundle(HostBundle.cursor)
        case .conductor:
            plan.target = .activateBundle(HostBundle.conductor)
        case .claudeApp:
            plan.target = .activateBundle(HostBundle.claudeApp)
        case .cli, .discovery:
            if let cwd { plan.target = .openTerminal(cwd: cwd) }
        case .demo:
            break
        }
        return plan
    }

    private static func target(for host: HostApp, terminal: TerminalContext, cwd: String?, titleHint: String?) -> JumpTarget {
        if host.isTmuxServer {
            return .tmuxClient(socket: terminal.tmuxSocket, pane: terminal.tmuxPane)
        }
        switch host.bundleID {
        case HostBundle.ghostty:
            return .ghostty(pid: host.pid, cwd: cwd, titleHint: titleHint)
        case HostBundle.appleTerminal:
            return .appleTerminal(pid: host.pid, tty: terminal.tty)
        case HostBundle.iterm:
            return .iterm(pid: host.pid, tty: terminal.tty)
        case HostBundle.kitty:
            return .kitty(pid: host.pid, windowID: terminal.kittyWindowID, listenOn: terminal.kittyListenOn)
        case HostBundle.wezterm:
            return .wezterm(pid: host.pid, pane: terminal.weztermPane)
        default:
            return .activate(pid: host.pid)
        }
    }

    // MARK: Ghostty matching

    /// Pick the surface running the session. Same directory first; among those, the tab whose
    /// title carries Claude's AI title, then any tab that isn't showing a bare shell prompt
    /// (Ghostty's shell integration titles idle shells `user@host:path`), then the first.
    /// With no directory match, a unique title hit still wins; otherwise give up rather than
    /// yank the user to an unrelated tab.
    static func chooseGhosttyTerminal(_ terminals: [GhosttyTerminal], cwd: String?, titleHint: String?) -> GhosttyTerminal? {
        let hint = titleHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        func carriesHint(_ terminal: GhosttyTerminal) -> Bool {
            guard let hint, !hint.isEmpty else { return false }
            return terminal.title.localizedCaseInsensitiveContains(hint)
        }

        let wanted = cwd.map(normalizePath)
        let sameDirectory = terminals.filter { wanted != nil && normalizePath($0.workingDirectory) == wanted }
        if !sameDirectory.isEmpty {
            if let hit = sameDirectory.first(where: carriesHint) { return hit }
            if let hit = sameDirectory.first(where: { !looksLikeShellPrompt($0.title) }) { return hit }
            return sameDirectory.first
        }

        let byTitle = terminals.filter(carriesHint)
        return byTitle.count == 1 ? byTitle[0] : nil
    }

    /// Ghostty reports plain paths today; tolerate `file://` URLs and `~` in case that changes.
    static func normalizePath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return "" }
        if path.hasPrefix("file://"), let url = URL(string: path) {
            path = url.path
        }
        path = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var result = url.path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// `mikaela@Alioth:~/Repositories/website` — what an idle shell paints.
    static func looksLikeShellPrompt(_ title: String) -> Bool {
        guard let at = title.firstIndex(of: "@"), at != title.startIndex else { return false }
        let afterAt = title[title.index(after: at)...]
        guard let colon = afterAt.firstIndex(of: ":") else { return false }
        return !title[..<at].contains(" ") && !afterAt[..<colon].contains(" ")
    }

    /// Parse the runner's AppleScript listing: fields split by U+001F, records by U+001E.
    static func parseGhosttyListing(_ text: String) -> [GhosttyTerminal] {
        text.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { return nil }
            return GhosttyTerminal(
                windowID: fields[0],
                tabID: fields[1],
                terminalID: fields[2],
                title: fields[3],
                workingDirectory: fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
