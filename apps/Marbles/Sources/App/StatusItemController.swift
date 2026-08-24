import AppKit

@MainActor
final class StatusItemController {
    private let overlay: OverlayController
    private let statusItem: NSStatusItem

    init(overlay: OverlayController) {
        self.overlay = overlay
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "Marbles"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = makeMenu()

        overlay.onVisibilityChange = { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

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
            action: nil,
            keyEquivalent: ""
        )
        hooks.isEnabled = false
        menu.addItem(hooks)

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
        debug.addItem(.separator())
        debug.addItem(item("Reset to 3 dummies", #selector(clearInjected)))
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
    @objc private func clearInjected() { overlay.clearDebugAgents() }
    @objc private func statusWorking() { overlay.setSelectedStatus(.working) }
    @objc private func statusThinking() { overlay.setSelectedStatus(.thinking) }
    @objc private func statusWaiting() { overlay.setSelectedStatus(.waitingOnUser) }
    @objc private func statusFinished() { overlay.setSelectedStatus(.finished) }
    @objc private func statusError() { overlay.setSelectedStatus(.error) }
    @objc private func cycleTool() { overlay.cycleSelectedTool() }
}
