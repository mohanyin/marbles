import AppKit

/// Owns the overlay panel. W1 will drive size and content; W0 is a single placeholder circle.
@MainActor
final class OverlayController {
    var onVisibilityChange: ((Bool) -> Void)?

    private var panel: OverlayPanel?
    private var overlayView: OverlayView?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    init() {}

    func show() {
        let panel = makePanelIfNeeded()
        if panel.frame.origin == .zero {
            panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        }
        panel.orderFrontRegardless()
        startMouseTracking()
        updateIgnoreMouseEvents()
        onVisibilityChange?(true)
    }

    func hide() {
        panel?.orderOut(nil)
        stopMouseTracking()
        onVisibilityChange?(false)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Screen-space test used to click through the square window around the circle.
    func containsScreenPoint(_ screenPoint: NSPoint) -> Bool {
        guard let panel, let overlayView, panel.isVisible else { return false }
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let viewPoint = overlayView.convert(windowPoint, from: nil)
        return overlayView.containsInteractivePoint(viewPoint)
    }

    private func makePanelIfNeeded() -> OverlayPanel {
        if let panel {
            return panel
        }

        let size = OverlayView.panelSize
        let panel = OverlayPanel(contentSize: size)
        let view = OverlayView(frame: NSRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.setContentSize(size)

        self.panel = panel
        self.overlayView = view
        return panel
    }

    private func defaultOrigin(for size: CGSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(
            x: screen.maxX - size.width - 12,
            y: screen.minY + 12
        )
    }

    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }

        // Global: events targeting other apps. Needed because a window with
        // ignoresMouseEvents = true does not receive local mouseMoved.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.updateIgnoreMouseEvents()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.updateIgnoreMouseEvents()
            return event
        }
    }

    private func stopMouseTracking() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        panel?.ignoresMouseEvents = false
    }

    private func updateIgnoreMouseEvents() {
        guard let panel, panel.isVisible else { return }
        let overMarble = containsScreenPoint(NSEvent.mouseLocation)
        let dragging = overlayView?.isDragging == true
        panel.ignoresMouseEvents = !(overMarble || dragging)
    }
}
