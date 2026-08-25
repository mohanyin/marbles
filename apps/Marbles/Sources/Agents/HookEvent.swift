import Foundation

struct HookEvent: Equatable {
    var hookEventName: String
    var sessionID: String
    var cwd: String?
    var transcriptPath: String?
    var toolName: String?
    var toolInputSummary: String?
    var lastAssistantMessage: String?
    var notificationType: String?
    var agentID: String?
    var agentType: String?
    var sessionEndReason: String?
    var sessionStartSource: String?
    var composerMode: String?
    var isBackgroundAgent: Bool?
    var stopStatus: String?
    var sourceHint: Source?
    var parseError: Bool
}

enum HookKind: Equatable {
    case sessionStart
    case sessionEnd
    case userPromptSubmit
    case preToolUse
    case postToolUse
    case postToolUseFailure
    case notification
    case permissionRequest
    case stop
    case stopFailure
    case subagentStart
    case subagentStop
    case afterAgentThought
    case afterAgentResponse
    case ignore
}

extension HookEvent {
    var kind: HookKind {
        switch hookEventName {
        case "SessionStart", "sessionStart":
            return .sessionStart
        case "SessionEnd", "sessionEnd":
            return .sessionEnd
        case "UserPromptSubmit", "beforeSubmitPrompt":
            return .userPromptSubmit
        case "PreToolUse", "preToolUse":
            return .preToolUse
        case "PostToolUse", "postToolUse":
            return .postToolUse
        case "PostToolUseFailure", "postToolUseFailure":
            return .postToolUseFailure
        case "Notification":
            return .notification
        case "PermissionRequest":
            return .permissionRequest
        case "Stop", "stop":
            return .stop
        case "StopFailure":
            return .stopFailure
        case "SubagentStart", "subagentStart":
            return .subagentStart
        case "SubagentStop", "subagentStop":
            return .subagentStop
        case "afterAgentThought":
            return .afterAgentThought
        case "afterAgentResponse":
            return .afterAgentResponse
        default:
            return .ignore
        }
    }
}
