import AppKit

@MainActor
final class OverlayController {
    var onVisibilityChange: ((Bool) -> Void)?

    let roster = AgentRoster()
    let mode = ModeController()

    private var panel: OverlayPanel?
    private var rootView: OverlayRootView?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var keyMonitor: Any?

    private var snap: SnapState = .snap(.bottomRight)
    private var scrollOffset: CGFloat = 0
    private var currentLayout: LayoutResult?
    private var animation: FrameAnimation?

    private var drag: DragState?
    private var lastInteractionWasOverlay = false

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private var focusedID: AgentID? {
        if case .focus(let id) = mode.mode { return id }
        return nil
    }

    init() {
        roster.replaceWithDebugDummies(count: 3)
        mode.onChange = { [weak self] _ in
            self?.scrollOffset = 0
            self?.relayout(animated: true)
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        relayout(animated: false)
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
        isVisible ? hide() : show()
    }

    func injectDebugAgents(count: Int) {
        roster.replaceWithDebugDummies(count: count)
        mode.resetToCluster()
        scrollOffset = 0
        relayout(animated: true)
    }

    func clearDebugAgents() {
        roster.replaceWithDebugDummies(count: 3)
        mode.resetToCluster()
        scrollOffset = 0
        relayout(animated: true)
    }

    var selectedAgentID: AgentID? {
        focusedID ?? roster.agents.first?.id
    }

    func setSelectedStatus(_ status: AgentStatus) {
        if let id = selectedAgentID {
            roster.setStatus(status, for: id)
            relayout(animated: false)
        }
    }

    func cycleSelectedTool() {
        if let id = selectedAgentID {
            roster.cycleTool(for: id)
            relayout(animated: false)
        }
    }

    func containsScreenPoint(_ screenPoint: NSPoint) -> Bool {
        guard let panel, let rootView, panel.isVisible else { return false }
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let viewPoint = rootView.convert(windowPoint, from: nil)
        return rootView.containsInteractivePoint(viewPoint)
    }

    private func makePanelIfNeeded() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(contentSize: CGSize(width: 52, height: 52))
        let view = OverlayRootView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        self.panel = panel
        self.rootView = view
        return panel
    }

    private func screenForPanel() -> NSScreen {
        panel?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func relayout(animated: Bool) {
        guard let panel else { return }
        let screen = screenForPanel()
        let safe = SnapGeometry.safeFrame(of: screen)
        let orientation = SnapGeometry.lineOrientation(
            snap: snap,
            panelOrigin: panel.frame.origin,
            panelSize: panel.frame.size,
            screen: screen
        )
        let available: CGFloat = orientation.axis == .vertical ? safe.height : safe.width
        let cardPositive = cardTowardPositive(snap: snap, panelOrigin: panel.frame.origin, panelSize: panel.frame.size, screen: screen)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let target = LayoutEngine.layout(
            agents: roster.agents,
            mode: mode.mode,
            orientation: orientation,
            scrollOffset: scrollOffset,
            availableLineLength: available,
            cardTowardPositivePerpendicular: cardPositive
        )

        let origin = SnapGeometry.panelOrigin(snap: snap, panelSize: target.panelSize, screen: screen)
        updateKeyStatus()
        rootView?.capturesEmptyClicks = mode.mode != .cluster

        if animated, !reduced, let current = currentLayout {
            let fromScreen = current.placed(inScreenAt: panel.frame.origin)
            let toScreen = target.placed(inScreenAt: origin)
            animation?.invalidate()
            animation = FrameAnimation(from: fromScreen, to: toScreen, duration: 0.28) { [weak self] interpolated in
                self?.applyScreenLayout(interpolated)
            } completion: { [weak self] in
                self?.apply(target, origin: origin)
            }
            animation?.start()
        } else {
            animation?.invalidate()
            animation = nil
            apply(target, origin: origin)
        }
    }

    private func apply(_ layout: LayoutResult, origin: CGPoint) {
        guard let panel, let rootView else { return }
        panel.setFrame(NSRect(origin: origin, size: layout.panelSize), display: true)
        rootView.frame = NSRect(origin: .zero, size: layout.panelSize)
        rootView.capturesEmptyClicks = mode.mode != .cluster
        rootView.apply(layout: layout, agents: roster.agents, focused: focusedID)
        currentLayout = layout
        updateIgnoreMouseEvents()
    }

    private func applyScreenLayout(_ screenLayout: LayoutResult) {
        let pair = screenLayout.localizedToPanel()
        apply(pair.local, origin: pair.origin)
    }

    private func updateKeyStatus() {
        guard let panel else { return }
        let wantsKey = mode.mode != .cluster
        panel.allowsKey = wantsKey
        if wantsKey {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        }
    }

    private func cardTowardPositive(snap: SnapState, panelOrigin: CGPoint, panelSize: CGSize, screen: NSScreen) -> Bool {
        let point: SnapPoint
        switch snap {
        case .snap(let value): point = value
        case .free: point = SnapGeometry.nearestPoint(panelOrigin: panelOrigin, panelSize: panelSize, screen: screen)
        }
        switch point {
        case .left, .topLeft, .bottomLeft, .bottom: return true
        case .right, .topRight, .bottomRight, .top: return false
        }
    }

    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .scrollWheel,
        ]) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobal(event)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown,
        ]) { [weak self] event in
            self?.handleLocal(event) ?? event
        }
    }

    private func stopMouseTracking() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        mouseMonitor = nil
        localMouseMonitor = nil
        keyMonitor = nil
        panel?.ignoresMouseEvents = false
    }

    private func handleGlobal(_ event: NSEvent) {
        updateIgnoreMouseEvents()
        if event.type == .leftMouseDown {
            let over = containsScreenPoint(NSEvent.mouseLocation)
            if !over, mode.mode != .cluster {
                mode.clickOutside()
                lastInteractionWasOverlay = false
            }
        }
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        updateIgnoreMouseEvents()
        switch event.type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            handleMouseDragged(event)
            return event
        case .leftMouseUp:
            handleMouseUp(event)
            return event
        case .scrollWheel:
            handleScroll(event)
            return event
        case .keyDown:
            if event.keyCode == 53 {
                handleEscape()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let panel, let rootView else { return event }
        let point = rootView.convert(event.locationInWindow, from: nil)
        switch rootView.hitTestKind(at: point) {
        case .none:
            if mode.mode != .cluster {
                lastInteractionWasOverlay = true
                mode.clickOutside()
                return nil
            }
            return event
        case .card:
            lastInteractionWasOverlay = true
            return event
        case .overflow:
            lastInteractionWasOverlay = true
            drag = DragState(startScreen: NSEvent.mouseLocation, startOrigin: panel.frame.origin, hit: .overflow)
            return nil
        case .marble(let id):
            lastInteractionWasOverlay = true
            updateKeyStatus()
            drag = DragState(startScreen: NSEvent.mouseLocation, startOrigin: panel.frame.origin, hit: .marble(id))
            return nil
        }
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard var drag, let panel else { return }
        let screen = NSEvent.mouseLocation
        let dx = screen.x - drag.startScreen.x
        let dy = screen.y - drag.startScreen.y
        if !drag.moved, hypot(dx, dy) >= 4 {
            drag.moved = true
            mode.beginDrag()
            self.drag = drag
        }
        guard drag.moved else { return }
        var origin = CGPoint(x: drag.startOrigin.x + dx, y: drag.startOrigin.y + dy)
        let visible = SnapGeometry.safeFrame(of: screenForPanel())
        origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
        snap = .free(
            x: Double(origin.x - screenForPanel().frame.origin.x),
            y: Double(origin.y - screenForPanel().frame.origin.y)
        )
        self.drag = drag
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard let drag else { return }
        defer { self.drag = nil }
        if drag.moved {
            if let panel {
                snap = SnapGeometry.resolveRelease(panelFrame: panel.frame, screen: screenForPanel())
                relayout(animated: true)
            }
            return
        }
        switch drag.hit {
        case .marble(let id):
            mode.clickMarble(id)
        case .overflow:
            mode.clickOverflow()
        case .card, .none:
            break
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard mode.mode != .cluster else { return }
        scrollOffset -= event.scrollingDeltaY
        relayout(animated: false)
    }

    private func handleEscape() {
        mode.escape()
    }

    private func updateIgnoreMouseEvents() {
        guard let panel, panel.isVisible else { return }
        if mode.mode != .cluster {
            panel.ignoresMouseEvents = false
            return
        }
        let over = containsScreenPoint(NSEvent.mouseLocation)
        let dragging = drag?.moved == true
        panel.ignoresMouseEvents = !(over || dragging)
    }
}

private struct DragState {
    var startScreen: NSPoint
    var startOrigin: NSPoint
    var hit: OverlayRootView.Hit
    var moved = false
}

private final class FrameAnimation {
    private let from: LayoutResult
    private let to: LayoutResult
    private let duration: TimeInterval
    private let onFrame: (LayoutResult) -> Void
    private let completion: () -> Void
    private var startedAt: Date?
    private var timer: Timer?

    init(
        from: LayoutResult,
        to: LayoutResult,
        duration: TimeInterval,
        onFrame: @escaping (LayoutResult) -> Void,
        completion: @escaping () -> Void
    ) {
        self.from = from
        self.to = to
        self.duration = duration
        self.onFrame = onFrame
        self.completion = completion
    }

    func start() {
        startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.004
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let startedAt else { return }
        let t = min(1, Date().timeIntervalSince(startedAt) / duration)
        let eased = 1 - pow(1 - t, 3)
        onFrame(Self.lerp(from, to, CGFloat(eased)))
        if t >= 1 {
            timer?.invalidate()
            timer = nil
            completion()
        }
    }

    private static func lerp(_ from: LayoutResult, _ to: LayoutResult, _ t: CGFloat) -> LayoutResult {
        var frames: [AgentID: MarbleFrame] = [:]
        let ids = Set(from.frames.keys).union(to.frames.keys)
        for id in ids {
            guard let end = to.frames[id] else { continue }
            let start = from.frames[id] ?? end
            frames[id] = MarbleFrame(
                center: CGPoint(
                    x: start.center.x + (end.center.x - start.center.x) * t,
                    y: start.center.y + (end.center.y - start.center.y) * t
                ),
                size: start.size + (end.size - start.size) * t,
                z: end.z,
                dim: start.dim + (end.dim - start.dim) * t
            )
        }
        return LayoutResult(
            frames: frames,
            overflow: t > 0.5 ? to.overflow : from.overflow,
            overflowFrame: lerp(from.overflowFrame, to.overflowFrame, t),
            focusCardFrame: lerp(from.focusCardFrame, to.focusCardFrame, t),
            panelSize: CGSize(
                width: from.panelSize.width + (to.panelSize.width - from.panelSize.width) * t,
                height: from.panelSize.height + (to.panelSize.height - from.panelSize.height) * t
            )
        )
    }

    private static func lerp(_ from: MarbleFrame?, _ to: MarbleFrame?, _ t: CGFloat) -> MarbleFrame? {
        guard let to else { return t > 0.5 ? nil : from }
        let start = from ?? to
        return MarbleFrame(
            center: CGPoint(
                x: start.center.x + (to.center.x - start.center.x) * t,
                y: start.center.y + (to.center.y - start.center.y) * t
            ),
            size: start.size + (to.size - start.size) * t,
            z: to.z,
            dim: start.dim + (to.dim - start.dim) * t
        )
    }

    private static func lerp(_ from: CGRect?, _ to: CGRect?, _ t: CGFloat) -> CGRect? {
        guard let to else { return t > 0.5 ? nil : from }
        let start = from ?? to
        return CGRect(
            x: start.origin.x + (to.origin.x - start.origin.x) * t,
            y: start.origin.y + (to.origin.y - start.origin.y) * t,
            width: start.size.width + (to.size.width - start.size.width) * t,
            height: start.size.height + (to.size.height - start.size.height) * t
        )
    }
}
