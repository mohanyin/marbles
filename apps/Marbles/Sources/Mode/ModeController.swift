import Foundation

enum OverlayMode: Equatable {
    case cluster
    case active
    case focus(AgentID)

    var focusedAgentID: AgentID? {
        if case .focus(let id) = self { return id }
        return nil
    }
}

@MainActor
final class ModeController {
    private(set) var mode: OverlayMode = .cluster
    var onChange: ((OverlayMode) -> Void)?

    func clickCluster() {
        guard mode == .cluster else { return }
        set(.active)
    }

    func clickOverflow() {
        if mode == .cluster {
            set(.active)
        }
    }

    func clickMarble(_ id: AgentID) {
        switch mode {
        case .cluster:
            set(.active)
        case .active:
            set(.focus(id))
        case .focus(let current):
            if current == id {
                set(.active)
            } else {
                set(.focus(id))
            }
        }
    }

    /// Active hover opens Focus. Focus hover on another marble switches. Cluster stays put.
    func hoverMarble(_ id: AgentID) {
        switch mode {
        case .cluster:
            break
        case .active:
            set(.focus(id))
        case .focus(let current):
            if current != id {
                set(.focus(id))
            }
        }
    }

    /// Desktop / empty chrome always packs back to Cluster.
    func clickOutside() {
        if mode != .cluster {
            set(.cluster)
        }
    }

    func escape() {
        switch mode {
        case .cluster:
            break
        case .active:
            set(.cluster)
        case .focus:
            set(.active)
        }
    }

    func beginDrag() {
        if mode != .cluster {
            set(.cluster)
        }
    }

    func resetToCluster() {
        set(.cluster)
    }

    private func set(_ mode: OverlayMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        onChange?(mode)
    }
}
