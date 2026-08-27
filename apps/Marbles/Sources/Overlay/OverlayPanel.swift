import AppKit

/// Non-activating overlay panel. Overlay owns window level and Spaces behavior.
final class OverlayPanel: NSPanel {
    /// Focus becomes key so Esc works without Input Monitoring permission.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    convenience init(contentSize: CGSize) {
        self.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}
