import Foundation

typealias AgentID = String

enum AgentStatus: Equatable {
    case working
    case thinking
    case waitingOnUser
    case finished
    case error
    case idle
}

enum Source: String, Codable {
    case cli, claudeApp, conductor, cursor, discovery, demo
}

struct ToolEvent: Equatable, Identifiable {
    var id: String
    var name: String
    var fileHint: String?
    var phase: Phase
    var at: Date

    enum Phase: Equatable {
        case started, succeeded, failed
    }
}

struct SubagentRecord: Equatable, Identifiable {
    var id: String
    var type: String?
    var startedAt: Date
}

struct Agent: Identifiable, Equatable {
    var id: AgentID
    var cwd: URL?
    var pid: Int32?
    var source: Source
    var conductorWorkspaceID: String?
    var status: AgentStatus
    var turnOpen: Bool
    var currentTool: ToolEvent?
    var recentTools: [ToolEvent]
    var lastAssistantPreview: String?
    var subagents: [SubagentRecord]
    var startedAt: Date
    var lastEventAt: Date
    var sessionEndedAt: Date?
    var seed: UInt64
    var latticeIndex: Int?
    var isDemo: Bool
    var animationTime: Float
    var bloomStartedAt: Date?
    var errorHueStartedAt: Date?
    var errorHueReleasedAt: Date?

    /// Debug-injected stand-ins. Distinct from `isDemo`, which hides first-launch placeholders from layout.
    var isInjected: Bool {
        source == .demo || id.hasPrefix("debug-")
    }

    static func make(
        id: AgentID,
        source: Source,
        status: AgentStatus = .idle,
        cwd: URL? = nil,
        conductorWorkspaceID: String? = nil,
        lastAssistantPreview: String? = nil,
        lastEventAt: Date? = nil,
        seed: UInt64? = nil,
        isDemo: Bool = false
    ) -> Agent {
        Agent(
            id: id,
            cwd: cwd,
            pid: nil,
            source: source,
            conductorWorkspaceID: conductorWorkspaceID,
            status: status,
            turnOpen: false,
            currentTool: nil,
            recentTools: [],
            lastAssistantPreview: lastAssistantPreview,
            subagents: [],
            startedAt: Date(),
            lastEventAt: lastEventAt ?? Date(),
            sessionEndedAt: nil,
            seed: seed ?? FNV.hash64(id),
            latticeIndex: nil,
            isDemo: isDemo,
            animationTime: 0,
            bloomStartedAt: nil,
            errorHueStartedAt: nil,
            errorHueReleasedAt: nil
        )
    }

    static func debugDummy(index: Int) -> Agent {
        make(
            id: "debug-\(index)",
            source: .demo,
            lastAssistantPreview: "Placeholder agent \(index + 1)",
            lastEventAt: Date().addingTimeInterval(TimeInterval(index))
        )
    }
}

enum SnapPoint: String, Codable, CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
}

enum SnapState: Codable, Equatable {
    case snap(SnapPoint)
    case free(x: Double, y: Double)
}

struct OverflowToken: Equatable {
    var hiddenCount: Int
}

enum FNV {
    static func hash64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
