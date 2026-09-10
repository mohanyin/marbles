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
        if handleHookCLI() {
            return
        }

        NSApp.setActivationPolicy(.accessory)

        let prefs = PrefsStore.shared
        let store = AgentStore()
        store.onCompletion = { _ in
            if prefs.values.completionSound { CompletionSound.play() }
        }

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
        self.overlay = overlay
        self.ingest = ingest

        syncHooksOnLaunch(prefs: prefs)
        discoverRunningSessions(store: store, prefs: prefs)

        if !prefs.values.overlayHidden {
            overlay.show()
        }
        statusItem = StatusItemController(overlay: overlay, prefs: prefs)
        confirmHooksIfNeeded(prefs: prefs)
        prefs.update { $0.didFirstLaunch = true }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay?.show()
        PrefsStore.shared.update { $0.overlayHidden = false }
        return false
    }

    private func handleHookCLI() -> Bool {
        if CommandLine.arguments.contains("--uninstall-hooks") {
            try? Hooks.undo()
            exit(0)
        }
        if CommandLine.arguments.contains("--install-hooks") {
            do {
                try Hooks.install()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("hook install failed\n".utf8))
                exit(1)
            }
        }
        return false
    }

    private func syncHooksOnLaunch(prefs: PrefsStore) {
        let first = !prefs.values.didFirstLaunch
        if first || Hooks.alreadyInstalled() {
            do {
                try Hooks.install()
                if first {
                    prefs.update { $0.pendingHookConfirmation = true }
                }
            } catch {
                return
            }
        }
    }

    /// Rebuilds the dock from sessions that are already running. The store is memory-only, so
    /// without this a restart shows nothing until each session next fires a hook — which for a
    /// session idling at a prompt can be hours. Scanning walks the transcript directory and the
    /// process table, so it runs off the main thread; the demo decision waits for the result so a
    /// machine with live sessions never gets a demo marble.
    private func discoverRunningSessions(store: AgentStore, prefs: PrefsStore) {
        Task.detached(priority: .utility) {
            let found = SessionDiscovery.scan()
            await MainActor.run {
                store.adoptDiscovered(found)
                self.offerDemoIfNeeded(store: store, prefs: prefs)
            }
        }
    }

    private func offerDemoIfNeeded(store: AgentStore, prefs: PrefsStore) {
        // A discovered session is activity in its own right, and a stronger signal than an mtime.
        let recent = !store.agents.isEmpty || SessionDiscovery.hasRecentClaudeActivity()
        if DemoMarble.shouldOffer(demoOffered: prefs.values.demoOffered, recentActivity: recent) {
            store.ensureDemo()
        }
        prefs.update { $0.demoOffered = true }
    }

    private func confirmHooksIfNeeded(prefs: PrefsStore) {
        guard prefs.values.pendingHookConfirmation else { return }
        prefs.update { $0.pendingHookConfirmation = false }
        let alert = NSAlert()
        alert.messageText = "Marbles hooks installed"
        alert.informativeText = "Claude Code and Cursor will send status to Marbles. Undo from the menu bar extra if you want them removed."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Undo")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            try? Hooks.undo()
            statusItem?.rebuild()
        }
    }
}
