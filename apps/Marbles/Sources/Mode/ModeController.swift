import Foundation

enum OverlayMode: Equatable {
    case dock
    case focus(AgentID)

    var focusedAgentID: AgentID? {
        if case .focus(let id) = self { return id }
        return nil
    }
}

@MainActor
final class ModeController {
    private(set) var mode: OverlayMode = .dock
    var onChange: ((OverlayMode) -> Void)?

    func clickMarble(_ id: AgentID) {
        set(.focus(id))
    }

    /// Hover opens Focus from Default and switches the focused agent.
    func hoverMarble(_ id: AgentID) {
        set(.focus(id))
    }

    /// Pointer left the dock pill and the Focus card.
    func hoverOff() {
        set(.dock)
    }

    /// Desktop, dock glass, or empty chrome.
    func clickOutside() {
        set(.dock)
    }

    func escape() {
        set(.dock)
    }

    func resetToDock() {
        set(.dock)
    }

    private func set(_ mode: OverlayMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        onChange?(mode)
    }
}
