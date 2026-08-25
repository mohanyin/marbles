import AppKit
import SwiftUI

@main
struct MarblesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var overlay: OverlayController?
    private var ingest: IngestServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AgentStore()
        store.injectDebugAgents(count: 3)

        let overlay = OverlayController(store: store)
        let ingest = IngestServer { data in
            Task { @MainActor in
                if let event = HookMapper.event(from: data) {
                    store.apply(event)
                }
            }
        }
        ingest.start()
        overlay.ingestURL = ingest.url
        overlay.ingestToken = ingest.token
        overlay.show()
        self.overlay = overlay
        self.ingest = ingest

        statusItem = StatusItemController(overlay: overlay)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay?.show()
        return false
    }
}
