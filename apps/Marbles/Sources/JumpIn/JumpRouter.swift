import Foundation

enum JumpKind: Equatable {
    case claudeCode
    case cursor
    case terminal
    case conductor
}

struct JumpDecision: Equatable {
    var visible: Bool
    var enabled: Bool
    var tooltip: String?
}

enum JumpRouter {
    static let claudeBundle = "com.anthropic.claude-code"
    static let cursorBundles = ["com.todesktop.230313mzl4w4u92", "com.cursor"]
    static let conductorBundle = "build.conductor.desktop"
    static let terminalBundles = [
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.apple.Terminal",
    ]

    static func decision(_ kind: JumpKind, agent: Agent, launcher: AppLaunching = WorkspaceLauncher.shared) -> JumpDecision {
        let visible = isVisible(kind, agent: agent)
        if !visible {
            return JumpDecision(visible: false, enabled: false, tooltip: nil)
        }
        if agent.isDemo || agent.isInjected {
            return JumpDecision(visible: true, enabled: false, tooltip: "Demo.")
        }
        switch kind {
        case .claudeCode:
            if launcher.applicationExists(bundleID: claudeBundle) {
                return JumpDecision(visible: true, enabled: true, tooltip: nil)
            }
            return JumpDecision(visible: true, enabled: false, tooltip: "Claude Code isn’t installed")
        case .cursor:
            if firstBundle(cursorBundles, launcher: launcher) != nil {
                return JumpDecision(visible: true, enabled: true, tooltip: nil)
            }
            return JumpDecision(visible: true, enabled: false, tooltip: "Cursor isn’t installed")
        case .terminal:
            if agent.cwd == nil {
                return JumpDecision(visible: true, enabled: false, tooltip: "No working directory")
            }
            if firstBundle(terminalBundles, launcher: launcher) == nil {
                return JumpDecision(visible: true, enabled: false, tooltip: "Can’t find this terminal")
            }
            return JumpDecision(visible: true, enabled: true, tooltip: nil)
        case .conductor:
            if launcher.applicationExists(bundleID: conductorBundle) {
                return JumpDecision(visible: true, enabled: true, tooltip: nil)
            }
            return JumpDecision(visible: true, enabled: false, tooltip: "Conductor isn’t installed")
        }
    }

    static func isVisible(_ kind: JumpKind, agent: Agent) -> Bool {
        switch kind {
        case .claudeCode:
            return agent.source != .cursor
        case .cursor:
            return agent.source == .cursor
        case .terminal:
            return true
        case .conductor:
            return agent.conductorWorkspaceID != nil || isConductorCWD(agent.cwd)
        }
    }

    static func open(_ kind: JumpKind, agent: Agent, launcher: AppLaunching = WorkspaceLauncher.shared) throws {
        let plan = decision(kind, agent: agent, launcher: launcher)
        guard plan.visible else { return }
        guard plan.enabled else {
            if agent.isDemo || agent.isInjected { throw JumpError.demo }
            if kind == .terminal { throw JumpError.noWorkingDirectory }
            throw JumpError.appMissing
        }
        switch kind {
        case .claudeCode:
            if let url = URL(string: "claude://claude.ai/chat/\(agent.id)") {
                try? launcher.open(url)
            }
            try launcher.openApplication(bundleID: claudeBundle)
        case .cursor:
            guard let bundle = firstBundle(cursorBundles, launcher: launcher) else {
                throw JumpError.appMissing
            }
            if let cwd = agent.cwd {
                try launcher.open(cwd, bundleID: bundle)
            } else {
                try launcher.openApplication(bundleID: bundle)
            }
        case .terminal:
            guard let cwd = agent.cwd else { throw JumpError.noWorkingDirectory }
            let bundle = preferredTerminal(launcher: launcher) ?? "com.apple.Terminal"
            try launcher.open(cwd, bundleID: bundle)
        case .conductor:
            try launcher.openApplication(bundleID: conductorBundle)
            if let cwd = agent.cwd {
                try? launcher.open(cwd, bundleID: conductorBundle)
            }
        }
    }

    static func isConductorCWD(_ cwd: URL?) -> Bool {
        guard let path = cwd?.path else { return false }
        return path.contains("/conductor/workspaces/")
    }

    private static func firstBundle(_ ids: [String], launcher: AppLaunching) -> String? {
        ids.first { launcher.applicationExists(bundleID: $0) }
    }

    private static func preferredTerminal(launcher: AppLaunching) -> String? {
        let running = launcher.runningBundleIDs()
        if let match = terminalBundles.first(where: { running.contains($0) && $0 != "com.apple.Terminal" }) {
            return match
        }
        return firstBundle(terminalBundles, launcher: launcher)
    }
}
