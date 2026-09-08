import AppKit
import SwiftUI

/// Accessory apps get no Settings menu, and the `showSettingsWindow:` action stopped
/// reaching the SwiftUI Settings scene on macOS 15, so the menu bar opens its own window.
@MainActor
final class PreferencesWindow {
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
        window.title = "Marbles Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
