import AppKit

@MainActor
final class OverlayController {
    var onVisibilityChange: ((Bool) -> Void)?
    var ingestURL: URL = IngestConstants.defaultURL()
    var ingestToken: String = ""

    let store: AgentStore
    let mode = ModeController()

    private var panel: OverlayPanel?
    private var rootView: OverlayRootView?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var keyMonitor: Any?

    private var snap: SnapState = .snap(.right)
    private var scrollOffset: CGFloat = 0
    private var currentLayout: LayoutResult?
    private var animation: FrameAnimation?

    private var drag: DragState?
    private var lastInteractionWasOverlay = false
    private var motionTimer: Timer?
    private var scrollSnapTimer: Timer?
    private var knownIDs: Set<AgentID> = []

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private var focusedID: AgentID? {
        mode.mode.focusedAgentID
    }

    init(store: AgentStore) {
        self.store = store
        knownIDs = Set(store.agents.map(\.id))
        mode.onChange = { [weak self] newMode in
            self?.handleModeChange(newMode)
        }
        store.onChange = { [weak self] in
            self?.handleStoreChange()
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        relayout(animated: false)
        panel.orderFrontRegardless()
        startMouseTracking()
        startMotionClock()
        updateIgnoreMouseEvents()
        onVisibilityChange?(true)
    }

    func hide() {
        panel?.orderOut(nil)
        stopMotionClock()
        stopMouseTracking()
        onVisibilityChange?(false)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func injectDebugAgents(count: Int) {
        store.injectDebugAgents(count: count)
        mode.resetToDock()
        scrollOffset = 0
    }

    func clearInjectedAgents() {
        store.clearInjected()
        mode.resetToDock()
        scrollOffset = 0
    }

    var selectedAgentID: AgentID? {
        focusedID ?? store.agents.first?.id
    }

    func setSelectedStatus(_ status: AgentStatus) {
        if let id = selectedAgentID {
            store.setStatus(status, for: id)
        }
    }

    func cycleSelectedTool() {
        if let id = selectedAgentID {
            store.cycleTool(for: id)
        }
    }

    func fireSelectedBloom() {
        if let id = selectedAgentID {
            store.fireBloom(for: id)
        }
    }

    func cycleSelectedSeed() {
        if let id = selectedAgentID {
            store.cycleSeed(for: id)
        }
    }

    func exportIdentitySheet() {
        let renderer = rootView?.metalRenderer ?? MarbleRenderer()
        guard let renderer, renderer.isReady else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for 100-marble identity sheets (PNG)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let written = IdentitySheet.write(using: renderer, to: url)
            if !written.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(written)
            }
        }
    }

    func replayFixture(named name: String) {
        guard let data = Self.fixtureData(named: name) else { return }
        let request = IngestAuth.hookRequest(url: ingestURL, body: data, token: ingestToken)
        URLSession.shared.dataTask(with: request).resume()
    }

    static func fixtureData(named name: String) -> Data? {
        if let data = FixtureFiles.data(named: name, startingAt: #filePath) { return data }
        return Bundle.main.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
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

    private func handleModeChange(_ newMode: OverlayMode) {
        if case .focus(let id) = newMode {
            scrollFocused(id)
        }
        relayout(animated: true)
    }

    private func handleStoreChange() {
        let ids = store.agents.map(\.id)
        let idSet = Set(ids)
        if case .focus(let id) = mode.mode, !idSet.contains(id) {
            mode.resetToDock()
        }
        let previous = knownIDs
        let rosterChanged = previous != idSet
        if previous.isEmpty {
            knownIDs = idSet
        } else {
            let inserted = ids.filter { !previous.contains($0) }
            knownIDs = idSet
            if mode.mode.focusedAgentID == nil, let newest = inserted.last, let index = ids.firstIndex(of: newest) {
                scrollOffset = LayoutEngine.scrollToReveal(
                    index: index,
                    count: ids.count,
                    available: availableLineLength(),
                    current: scrollOffset
                )
            }
        }
        if rosterChanged, let focused = mode.mode.focusedAgentID {
            scrollFocused(focused)
        }
        relayout(animated: true)
    }

    private func scrollFocused(_ id: AgentID) {
        let ids = store.agents.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        scrollOffset = LayoutEngine.scrollToReveal(
            index: index,
            count: ids.count,
            available: availableLineLength(),
            current: scrollOffset
        )
    }

    private func availableLineLength() -> CGFloat {
        let screen = screenForPanel()
        let safe = SnapGeometry.safeFrame(of: screen)
        let orientation = SnapGeometry.lineOrientation(
            snap: snap,
            panelOrigin: panel?.frame.origin ?? .zero,
            panelSize: panel?.frame.size ?? .zero,
            screen: screen
        )
        return orientation.axis == .vertical ? safe.height : safe.width
    }

    private func currentPoint() -> SnapPoint {
        switch snap {
        case .snap(let point):
            return point
        case .free:
            let screen = screenForPanel()
            return SnapGeometry.nearestPoint(
                panelOrigin: panel?.frame.origin ?? .zero,
                panelSize: panel?.frame.size ?? .zero,
                screen: screen
            )
        }
    }

    /// Measured size of the card for the focused agent. `.zero` when nothing is focused —
    /// `LayoutEngine` only reads it when a hero marble resolves.
    private func focusCardSize() -> CGSize {
        guard let id = focusedID, let agent = store.agent(id: id) else { return .zero }
        return FocusCardMetrics.size(
            title: FocusPreview.title(for: agent),
            prompt: FocusPreview.prompt(for: agent),
            turn: agent.turn,
            fallback: FocusPreview.line(for: agent)
        )
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
        let cardPositive = SnapGeometry.cardTowardPositive(for: currentPoint())
        let reduced = prefersReducedMotion
        let target = LayoutEngine.layout(
            agents: store.agents,
            mode: mode.mode,
            orientation: orientation,
            scrollOffset: scrollOffset,
            availableLineLength: available,
            cardTowardPositivePerpendicular: cardPositive,
            focusCardSize: focusCardSize()
        )
        scrollOffset = target.scrollOffset

        let origin = SnapGeometry.panelOrigin(
            snap: snap,
            dockFrame: target.dockFrame,
            panelSize: target.panelSize,
            screen: screen
        )
        updateKeyStatus()

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
        rootView.reducedMotion = prefersReducedMotion
        rootView.apply(layout: layout, agents: store.agents, focused: focusedID, mode: mode.mode)
        currentLayout = layout
        updateIgnoreMouseEvents()
    }

    private func applyScreenLayout(_ screenLayout: LayoutResult) {
        let pair = screenLayout.localizedToPanel()
        apply(pair.local, origin: pair.origin)
    }

    private func updateKeyStatus() {
        guard let panel else { return }
        let wantsKey = mode.mode != .dock
        panel.allowsKey = wantsKey
        if wantsKey {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
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

    private func startMotionClock() {
        stopMotionClock()
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMotion()
            }
        }
        motionTimer?.tolerance = 0.004
    }

    private func stopMotionClock() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func tickMotion() {
        let reduced = prefersReducedMotion
        store.advanceAnimationTime(1.0 / 60.0, reducedMotion: reduced)
        rootView?.tickMotion(agents: store.agents, reducedMotion: reduced)
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
        if event.type == .mouseMoved {
            handleHover()
        }
        if event.type == .leftMouseDown {
            let over = containsScreenPoint(NSEvent.mouseLocation)
            if !over, mode.mode != .dock {
                mode.clickOutside()
                lastInteractionWasOverlay = false
            }
        }
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        updateIgnoreMouseEvents()
        switch event.type {
        case .mouseMoved:
            handleHover()
            return event
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

    private func handleHover() {
        guard drag == nil, NSEvent.pressedMouseButtons == 0 else { return }
        guard let panel, let rootView, panel.isVisible else { return }
        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = rootView.convert(windowPoint, from: nil)
        switch rootView.hitTestKind(at: point) {
        case .marble(let id):
            mode.hoverMarble(id)
        case .card, .dock:
            break
        case .none:
            if mode.mode != .dock {
                mode.hoverOff()
            }
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let panel, let rootView else { return event }
        let point = rootView.convert(event.locationInWindow, from: nil)
        let focused = mode.mode != .dock
        let kind = rootView.hitTestKind(at: point, hoverSlop: false)
        switch kind {
        case .none:
            if focused {
                lastInteractionWasOverlay = true
                mode.clickOutside()
                return nil
            }
            return event
        case .card:
            lastInteractionWasOverlay = true
            return event
        case .dock, .marble:
            lastInteractionWasOverlay = true
            if case .marble = kind { updateKeyStatus() }
            // Arm a drag even while Focus is open. Hovering a marble opens Focus, so gating the
            // drag on `!focused` meant the only draggable spots were the dock margins between
            // marbles. Click vs. drag is settled on mouse-up by `drag.moved`.
            drag = DragState(
                startScreen: NSEvent.mouseLocation,
                startOrigin: panel.frame.origin,
                hit: kind,
                wasFocused: focused
            )
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
            self.drag = drag
        }
        guard drag.moved else { return }
        var origin = CGPoint(x: drag.startOrigin.x + dx, y: drag.startOrigin.y + dy)
        let visible = SnapGeometry.safeFrame(of: screenForPanel())
        // Keep the *dock* on screen, not the panel: with Focus open the panel also spans the
        // card, and clamping that would stop the dock well short of the screen edges.
        let dockRect = currentLayout?.dockFrame ?? CGRect(origin: .zero, size: panel.frame.size)
        var dockOrigin = CGPoint(x: origin.x + dockRect.minX, y: origin.y + dockRect.minY)
        dockOrigin.x = min(max(dockOrigin.x, visible.minX), visible.maxX - dockRect.width)
        dockOrigin.y = min(max(dockOrigin.y, visible.minY), visible.maxY - dockRect.height)
        origin = CGPoint(x: dockOrigin.x - dockRect.minX, y: dockOrigin.y - dockRect.minY)
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
            if let panel, let layout = currentLayout {
                let dock = layout.dockFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
                snap = SnapGeometry.resolveDockRelease(dockFrame: dock, screen: screenForPanel())
                relayout(animated: true)
            }
            return
        }
        // A press that never moved is a click.
        switch drag.hit {
        case .marble(let id):
            mode.clickMarble(id)
        case .dock:
            if drag.wasFocused { mode.clickOutside() }
        case .card, .none:
            break
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let orientation = SnapGeometry.orientation(for: currentPoint())
        let along: CGFloat
        switch orientation.axis {
        case .vertical:
            along = event.scrollingDeltaY
        case .horizontal:
            along = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        }
        scrollOffset -= along
        relayout(animated: false)
        scrollSnapTimer?.invalidate()
        scrollSnapTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.snapScrollToItem()
            }
        }
    }

    private func snapScrollToItem() {
        let layout = currentLayout
        let maxScroll = layout?.maxScroll ?? 0
        scrollOffset = LayoutEngine.snapScroll(scrollOffset, maxScroll: maxScroll)
        relayout(animated: true)
    }

    private func handleEscape() {
        mode.escape()
    }

    private func updateIgnoreMouseEvents() {
        guard let panel, panel.isVisible else { return }
        let over = containsScreenPoint(NSEvent.mouseLocation)
        let dragging = drag?.moved == true
        panel.ignoresMouseEvents = !(over || dragging || mode.mode != .dock)
        if mode.mode != .dock {
            panel.ignoresMouseEvents = false
        }
    }

    private var prefersReducedMotion: Bool {
        PrefsStore.shared.values.reducedMotion
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

private struct DragState {
    var startScreen: NSPoint
    var startOrigin: NSPoint
    var hit: OverlayRootView.Hit
    /// Focus was open when the press landed — a press that never moves dismisses it on release.
    var wasFocused: Bool
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
                dim: 0
            )
        }
        return LayoutResult(
            frames: frames,
            dockFrame: lerp(from.dockFrame, to.dockFrame, t),
            focusCardFrame: lerp(from.focusCardFrame, to.focusCardFrame, t),
            panelSize: CGSize(
                width: from.panelSize.width + (to.panelSize.width - from.panelSize.width) * t,
                height: from.panelSize.height + (to.panelSize.height - from.panelSize.height) * t
            ),
            scrollOffset: from.scrollOffset + (to.scrollOffset - from.scrollOffset) * t,
            maxScroll: to.maxScroll,
            visibleCount: t > 0.5 ? to.visibleCount : from.visibleCount,
            orientation: to.orientation
        )
    }

    private static func lerp(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * t,
            y: from.origin.y + (to.origin.y - from.origin.y) * t,
            width: from.size.width + (to.size.width - from.size.width) * t,
            height: from.size.height + (to.size.height - from.size.height) * t
        )
    }

    private static func lerp(_ from: CGRect?, _ to: CGRect?, _ t: CGFloat) -> CGRect? {
        guard let to else { return t > 0.5 ? nil : from }
        let start = from ?? to
        return lerp(start, to, t)
    }
}
