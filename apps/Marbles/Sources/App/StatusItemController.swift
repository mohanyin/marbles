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
}
