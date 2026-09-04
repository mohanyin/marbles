import AppKit
import Foundation

enum HookFileState: Equatable {
    case installed
    case missing
    case error
}

struct HookChecklist: Equatable {
    var claudeHooks: HookFileState
    var cursorHooks: HookFileState
    var claudeCodeDetected: Bool
    var cursorDetected: Bool
    var conductorDetected: Bool
}

enum Hooks {
    static let marker = "marbles-hook"

    static let claudeEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SubagentStart",
        "SubagentStop", "PermissionRequest",
    ]

    static let cursorEvents = [
        "sessionStart", "sessionEnd", "beforeSubmitPrompt", "preToolUse", "postToolUse",
        "postToolUseFailure", "stop", "subagentStart", "subagentStop", "afterAgentThought",
        "afterAgentResponse",
    ]

    struct Files {
        var claude: URL
        var cursor: URL
        var helper: URL
    }

    enum HookError: Error, Equatable {
        case invalidClaude
        case invalidCursor
        case writeFailed
    }

    static var defaultFiles: Files {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Files(
            claude: home.appendingPathComponent(".claude/settings.json"),
            cursor: home.appendingPathComponent(".cursor/hooks.json"),
            helper: helperURL()
        )
    }

    static func helperURL(bundle: Bundle = .main) -> URL {
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/marbles-hook")
    }

    static func command(for helper: URL) -> String {
        let path = helper.path
        if path.contains(" ") {
            return "\"\(path)\""
        }
        return path
    }

    static func isOwned(_ command: String) -> Bool {
        command.contains(marker)
    }

    @discardableResult
    static func install(files: Files? = nil) throws -> Files {
        let files = files ?? defaultFiles
        try mergeClaude(at: files.claude, helper: files.helper)
        try mergeCursor(at: files.cursor, helper: files.helper)
        return files
    }

    static func undo(files: Files? = nil) throws {
        let files = files ?? defaultFiles
        try removeOwned(at: files.claude, style: .claude)
        try removeOwned(at: files.cursor, style: .cursor)
    }

    static func inspect(files: Files? = nil) -> (claude: HookFileState, cursor: HookFileState) {
        let files = files ?? defaultFiles
        return (state(at: files.claude, events: claudeEvents, style: .claude),
                state(at: files.cursor, events: cursorEvents, style: .cursor))
    }

    static func checklist(files: Files? = nil) -> HookChecklist {
        let hooks = inspect(files: files)
        return HookChecklist(
            claudeHooks: hooks.claude,
            cursorHooks: hooks.cursor,
            claudeCodeDetected: appExists("com.anthropic.claude-code") || binaryExists("claude"),
            cursorDetected: appExists("com.todesktop.230313mzl4w4u92") || appExists("com.cursor"),
            conductorDetected: appExists(HostBundle.conductor) || appExists(HostBundle.conductorLegacy)
        )
    }

    static func alreadyInstalled(files: Files? = nil) -> Bool {
        let state = inspect(files: files)
        return state.claude == .installed || state.cursor == .installed
    }

    private enum Style {
        case claude, cursor
    }

    private static func mergeClaude(at url: URL, helper: URL) throws {
        try merge(at: url, helper: helper, events: claudeEvents, style: .claude, extra: nil)
    }

    private static func mergeCursor(at url: URL, helper: URL) throws {
        try merge(at: url, helper: helper, events: cursorEvents, style: .cursor, extra: ["version": 1])
    }

    private static func merge(at url: URL, helper: URL, events: [String], style: Style, extra: [String: Any]?) throws {
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var object: [String: Any]
        if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object = extra ?? [:]
        } else {
            do {
                object = try JSONC.parseObject(original)
            } catch {
                throw style == .claude ? HookError.invalidClaude : HookError.invalidCursor
            }
            extra?.forEach { key, value in
                if object[key] == nil {
                    object[key] = value
                }
            }
        }
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        let command = command(for: helper)
        for event in events {
            hooks[event] = upsert(hooks[event], command: command, style: style)
        }
        object["hooks"] = hooks
        try write(object, to: url, original: original)
    }

    private static func removeOwned(at url: URL, style: Style) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let object: [String: Any]
        do {
            object = try JSONC.parseObject(original)
        } catch {
            throw style == .claude ? HookError.invalidClaude : HookError.invalidCursor
        }
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        for key in hooks.keys {
            hooks[key] = stripOwned(hooks[key], style: style)
        }
        var next = object
        next["hooks"] = hooks
        try write(next, to: url, original: original)
    }

    private static func upsert(_ existing: Any?, command: String, style: Style) -> Any {
        switch style {
        case .claude:
            var groups = existing as? [[String: Any]] ?? []
            groups = groups.map { group in
                var next = group
                var inner = next["hooks"] as? [[String: Any]] ?? []
                inner.removeAll { isOwned(($0["command"] as? String) ?? "") }
                next["hooks"] = inner
                return next
            }
            if !groups.contains(where: { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains { isOwned(($0["command"] as? String) ?? "") }
            }) {
                if groups.isEmpty {
                    groups.append(["hooks": [claudeCommand(command)]])
                } else {
                    var first = groups[0]
                    var inner = first["hooks"] as? [[String: Any]] ?? []
                    inner.append(claudeCommand(command))
                    first["hooks"] = inner
                    groups[0] = first
                }
            }
            return groups
        case .cursor:
            var items = existing as? [[String: Any]] ?? []
            items.removeAll { isOwned(($0["command"] as? String) ?? "") }
            items.append(["command": command])
            return items
        }
    }

    private static func stripOwned(_ existing: Any?, style: Style) -> Any {
        switch style {
        case .claude:
            let groups = (existing as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var next = group
                let inner = (next["hooks"] as? [[String: Any]] ?? []).filter { !isOwned(($0["command"] as? String) ?? "") }
                if inner.isEmpty, group.keys.contains("hooks") {
                    return nil
                }
                next["hooks"] = inner
                return next
            }
            return groups
        case .cursor:
            return (existing as? [[String: Any]] ?? []).filter { !isOwned(($0["command"] as? String) ?? "") }
        }
    }

    private static func claudeCommand(_ command: String) -> [String: Any] {
        ["type": "command", "command": command, "async": true]
    }

    private static func state(at url: URL, events: [String], style: Style) -> HookFileState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let object: [String: Any]
        do {
            object = try JSONC.parseObject(text)
        } catch {
            return .error
        }
        let hooks = object["hooks"] as? [String: Any] ?? [:]
        let complete = events.allSatisfy { event in
            containsOwned(hooks[event], style: style)
        }
        return complete ? .installed : .missing
    }

    private static func containsOwned(_ existing: Any?, style: Style) -> Bool {
        switch style {
        case .claude:
            return ((existing as? [[String: Any]]) ?? []).contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains { isOwned(($0["command"] as? String) ?? "") }
            }
        case .cursor:
            return ((existing as? [[String: Any]]) ?? []).contains { isOwned(($0["command"] as? String) ?? "") }
        }
    }

    private static func write(_ object: [String: Any], to url: URL, original: String) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = try JSONC.stringify(object, preservingCommentsFrom: original)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HookError.writeFailed
        }
    }

    private static func appExists(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func binaryExists(_ name: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/\(name)")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/\(name)")
            || FileManager.default.isExecutableFile(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local/bin/\(name)").path
            )
    }
}
