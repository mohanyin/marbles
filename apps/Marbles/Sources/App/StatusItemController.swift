import AppKit

@MainActor
final class StatusItemController {
    private let overlay: OverlayController
    private let prefs: PrefsStore
    private let statusItem: NSStatusItem

    init(overlay: OverlayController, prefs: PrefsStore = .shared) {
        self.overlay = overlay
        self.prefs = prefs
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "Marbles"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = makeMenu()

        overlay.onVisibilityChange = { [weak self] visible in
            self?.prefs.update { $0.overlayHidden = !visible }
            self?.rebuild()
        }
    }

    func rebuild() {
        statusItem.menu = makeMenu()
    }

    private func rebuildMenu() {
        rebuild()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let checklist = Hooks.checklist()

        let toggle = NSMenuItem(
            title: overlay.isVisible ? "Hide Overlay" : "Show Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let preferences = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferences.target = self
        menu.addItem(preferences)

        let hooks = NSMenuItem(
            title: "Install / Repair Hooks",
            action: #selector(installHooks),
            keyEquivalent: ""
        )
        hooks.target = self
        menu.addItem(hooks)

        let undo = NSMenuItem(
            title: "Undo Hooks",
            action: #selector(undoHooks),
            keyEquivalent: ""
        )
        undo.target = self
        undo.isEnabled = checklist.claudeHooks == .installed || checklist.cursorHooks == .installed
        menu.addItem(undo)

        let setup = NSMenuItem(title: "Setup", action: nil, keyEquivalent: "")
        setup.submenu = makeChecklistMenu(checklist)
        menu.addItem(setup)

        menu.addItem(.separator())

        #if DEBUG
        let debug = NSMenu(title: "Debug")
        debug.addItem(item("Inject 3 dummy agents", #selector(inject3)))
        debug.addItem(item("Inject 9 dummy agents", #selector(inject9)))
        debug.addItem(item("Inject 27 dummy agents", #selector(inject27)))
        debug.addItem(item("Inject 28 dummy agents", #selector(inject28)))
        debug.addItem(.separator())
        debug.addItem(item("Set selected → Working", #selector(statusWorking)))
        debug.addItem(item("Set selected → Thinking", #selector(statusThinking)))
        debug.addItem(item("Set selected → Waiting", #selector(statusWaiting)))
        debug.addItem(item("Set selected → Finished", #selector(statusFinished)))
        debug.addItem(item("Set selected → Error", #selector(statusError)))
        debug.addItem(item("Cycle current tool", #selector(cycleTool)))
        debug.addItem(item("Cycle selected seed", #selector(cycleSeed)))
        debug.addItem(item("Fire completion bloom", #selector(fireBloom)))
        debug.addItem(item("Export identity sheet…", #selector(exportSheet)))
        debug.addItem(.separator())
        debug.addItem(item("Replay SessionStart fixture", #selector(replayStart)))
        debug.addItem(item("Replay UserPrompt fixture", #selector(replayPrompt)))
        debug.addItem(item("Replay PreToolUse fixture", #selector(replayTool)))
        debug.addItem(item("Replay Stop fixture", #selector(replayStop)))
        debug.addItem(item("Replay StopFailure fixture", #selector(replayFail)))
        debug.addItem(item("Replay Cursor SessionStart", #selector(replayCursor)))
        debug.addItem(.separator())
        debug.addItem(item("Clear all injected", #selector(clearInjected)))
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = debug
        menu.addItem(debugItem)
        menu.addItem(.separator())
        #endif

        let about = NSMenuItem(
            title: "About Marbles",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Marbles",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func makeChecklistMenu(_ checklist: HookChecklist) -> NSMenu {
        let menu = NSMenu(title: "Setup")
        menu.addItem(info("Claude hooks: \(label(checklist.claudeHooks))"))
        menu.addItem(info("Cursor hooks: \(label(checklist.cursorHooks))"))
        menu.addItem(info("Claude Code: \(checklist.claudeCodeDetected ? "Detected" : "Not found")"))
        menu.addItem(info("Cursor: \(checklist.cursorDetected ? "Detected" : "Not found")"))
        menu.addItem(info("Conductor: \(checklist.conductorDetected ? "Detected" : "Not found")"))
        menu.addItem(.separator())
        menu.addItem(info("Start a Claude Code or Cursor Agent session to see a live marble."))
        return menu
    }

    private func label(_ state: HookFileState) -> String {
        switch state {
        case .installed: return "Installed"
        case .missing: return "Missing"
        case .error: return "Error"
        }
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleOverlay() {
        overlay.toggle()
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func installHooks() {
        do {
            try Hooks.install()
            let alert = NSAlert()
            alert.messageText = "Hooks installed"
            alert.informativeText = "Restart any already-open Claude Code session to connect it. New sessions pick up hooks immediately."
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t install hooks"
            alert.informativeText = "A settings file looks invalid, so Marbles left it alone. Fix the JSON and try Repair."
            alert.runModal()
        }
        rebuild()
    }

    @objc private func undoHooks() {
        do {
            try Hooks.undo()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t undo hooks"
            alert.informativeText = "A settings file looks invalid, so Marbles left it alone."
            alert.runModal()
        }
        rebuild()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func inject3() { overlay.injectDebugAgents(count: 3) }
    @objc private func inject9() { overlay.injectDebugAgents(count: 9) }
    @objc private func inject27() { overlay.injectDebugAgents(count: 27) }
    @objc private func inject28() { overlay.injectDebugAgents(count: 28) }
    @objc private func clearInjected() { overlay.clearInjectedAgents() }
    @objc private func statusWorking() { overlay.setSelectedStatus(.working) }
    @objc private func statusThinking() { overlay.setSelectedStatus(.thinking) }
    @objc private func statusWaiting() { overlay.setSelectedStatus(.waitingOnUser) }
    @objc private func statusFinished() { overlay.setSelectedStatus(.finished) }
    @objc private func statusError() { overlay.setSelectedStatus(.error) }
    @objc private func cycleTool() { overlay.cycleSelectedTool() }
    @objc private func cycleSeed() { overlay.cycleSelectedSeed() }
    @objc private func fireBloom() { overlay.fireSelectedBloom() }
    @objc private func exportSheet() { overlay.exportIdentitySheet() }
    @objc private func replayStart() { overlay.replayFixture(named: "session-start") }
    @objc private func replayPrompt() { overlay.replayFixture(named: "user-prompt") }
    @objc private func replayTool() { overlay.replayFixture(named: "pre-tool-use") }
    @objc private func replayStop() { overlay.replayFixture(named: "stop") }
    @objc private func replayFail() { overlay.replayFixture(named: "stop-failure") }
    @objc private func replayCursor() { overlay.replayFixture(named: "cursor-session-start") }
}
