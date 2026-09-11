import Foundation
import SQLite3

/// Reads the title Conductor generates for a workspace session.
///
/// A Conductor session is driven by injected instructions rather than a typed prompt, so Claude
/// Code never generates an `ai-title` for it and there is no first prompt to summarize — the
/// marble would otherwise be nameless. Conductor does generate a short title of its own ("Daily
/// Brief"), which is exactly the label the card wants, so it is read rather than reinvented.
///
/// The title lives in Conductor's SQLite store, joined from the workspace whose `workspace_path`
/// matches the session's working directory. The database is opened **read-only** and immutably:
/// Conductor owns it, and is very likely running while this reads.
enum ConductorWorkspace {
    /// Conductor's support directory, holding `conductor.db`.
    static var databaseURL: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.conductor.app/conductor.db")
            .expandingTildeInPath)
    }

    /// True when `cwd` sits inside a Conductor workspace checkout.
    static func isConductor(cwd: String?) -> Bool {
        cwd?.contains("/conductor/workspaces/") ?? false
    }

    /// The title Conductor shows for the session running in `cwd`, or nil when there is none.
    ///
    /// `Untitled` is Conductor's placeholder before it has named the session, and an empty title
    /// means the same thing — both are treated as absent so a weaker source can still apply.
    static func title(forCWD cwd: String?, database: URL? = nil) -> String? {
        guard isConductor(cwd: cwd), let cwd else { return nil }
        let path = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let query = """
        SELECT s.title FROM workspaces w \
        JOIN sessions s ON w.active_session_id = s.id \
        WHERE w.workspace_path = ? LIMIT 1;
        """
        guard let title = SQLite.firstString(
            database: database ?? databaseURL,
            query: query,
            bind: [path]
        ) else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Untitled") != .orderedSame else {
            return nil
        }
        return trimmed
    }
}

/// The little of SQLite needed to read one string out of another app's database.
///
/// Opened read-only, but *not* `immutable`. Conductor keeps a large write-ahead log, and the rows
/// for a session it just created live there rather than in the main file — the titles this needs
/// most are the newest ones. `immutable=1` skips the WAL and silently returns nothing for them,
/// so the read has to be WAL-aware; read-only keeps it from disturbing the owning app.
/// Linked against the system `libsqlite3`, so there is no dependency to vendor.
enum SQLite {
    static func firstString(database: URL, query: String, bind: [String] = []) -> String? {
        guard FileManager.default.isReadableFile(atPath: database.path) else { return nil }
        let uri = "file:\(database.path)?mode=ro"
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle else {
            if handle != nil { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bind.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }
}

/// `SQLITE_TRANSIENT` tells SQLite to copy the bound string; it is a macro, so it is unavailable
/// to Swift and has to be rebuilt from its value.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
