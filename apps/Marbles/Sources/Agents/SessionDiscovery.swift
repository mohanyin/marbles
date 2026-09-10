import Foundation

/// Finds Claude sessions that are running but have not sent a hook yet (ARCHITECTURE §11.5).
///
/// The agent list is built from hook events, so it is empty every time the app starts and stays
/// empty for an idle session until its next event — which, for a session sitting at a prompt,
/// may be hours. Scanning the transcript directory rebuilds the board on launch instead.
///
/// A transcript on its own is not evidence of a live session: `~/.claude/projects` accumulates
/// every conversation ever held. A candidate must therefore pair a recently written transcript
/// with a live `claude` process, and even then the count is capped — a stale marble that cannot
/// be clicked into is worse than a missing one.
enum SessionDiscovery {
    /// Only transcripts written this recently are considered (§8 idle discovery cap).
    static let freshness: TimeInterval = 2 * 60 * 60
    /// At most this many discovered agents, so a busy machine cannot flood the dock.
    static let maxAgents = 5

    struct Candidate: Equatable {
        var sessionID: String
        var transcriptPath: String
        var cwd: String?
        var pid: Int32
        var modifiedAt: Date
    }

    /// Live sessions worth showing, newest transcript first.
    static func scan(
        root: URL? = nil,
        now: Date = Date(),
        pids: [Int32]? = nil
    ) -> [Candidate] {
        let directory = root ?? defaultRoot
        let live = pids ?? claudePIDs()
        guard !live.isEmpty else { return [] }
        var byCWD = [String: [Int32]]()
        for pid in live {
            guard let cwd = ProcessTree.cwd(of: pid) else { continue }
            byCWD[cwd, default: []].append(pid)
        }
        var claimed = Set<Int32>()
        var found: [Candidate] = []
        for transcript in transcripts(in: directory, since: now.addingTimeInterval(-freshness)) {
            // The cwd is recorded inside the transcript; the encoded folder name is lossy
            // (slashes and dots both become dashes) so it cannot be decoded back reliably.
            guard let cwd = TranscriptPeek.recordedCWD(path: transcript.path) else { continue }
            guard let candidates = byCWD[cwd] else { continue }
            guard let pid = candidates.first(where: { !claimed.contains($0) }) else { continue }
            claimed.insert(pid)
            found.append(
                Candidate(
                    sessionID: (transcript.path as NSString).lastPathComponent
                        .replacingOccurrences(of: ".jsonl", with: ""),
                    transcriptPath: transcript.path,
                    cwd: cwd,
                    pid: pid,
                    modifiedAt: transcript.modified
                )
            )
            if found.count >= maxAgents { break }
        }
        return found
    }

    static var defaultRoot: URL {
        URL(fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath)
    }

    /// Transcripts modified since `cutoff`, newest first.
    static func transcripts(in root: URL, since cutoff: Date) -> [(path: String, modified: Date)] {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        var files: [(path: String, modified: Date)] = []
        for project in projects {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for entry in entries where entry.pathExtension == "jsonl" {
                guard let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate else { continue }
                guard modified >= cutoff else { continue }
                files.append((entry.path, modified))
            }
        }
        return files.sorted { $0.modified > $1.modified }
    }

    /// Whether any transcript was written recently — the signal that decides whether the demo
    /// marble is offered on first launch.
    static func hasRecentClaudeActivity(
        now: Date = Date(),
        window: TimeInterval = DemoMarble.discoveryWindow,
        projects: URL? = nil
    ) -> Bool {
        let root = projects ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        let cutoff = now.addingTimeInterval(-window)
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date >= cutoff {
                return true
            }
        }
        return false
    }

    /// PIDs of running agent CLIs.
    ///
    /// Claude Code overwrites its process name with its own version string ("2.1.265"), so a
    /// plain name match finds nothing — the same reason `TerminalContext` matches on
    /// `looksLikeVersion` when it walks the ancestor chain.
    static func claudePIDs() -> [Int32] {
        ProcessTree.allPIDs().filter { pid in
            guard let name = ProcessTree.info(of: pid)?.name else { return false }
            return name == "claude" || name == "cursor-agent" || TerminalContext.looksLikeVersion(name)
        }
    }
}

extension ProcessTree {
    /// Every live PID, via `sysctl` — no subprocess.
    static func allPIDs() -> [Int32] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        let actual = size / MemoryLayout<kinfo_proc>.stride
        return procs.prefix(actual).map { $0.kp_proc.p_pid }.filter { $0 > 0 }
    }

    /// Working directory of a process, via the same `proc_pidinfo` call `lsof` uses.
    static func cwd(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pointer, Int32(size))
        }
        guard result == Int32(size) else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let path = String(cString: $0)
                return path.isEmpty ? nil : path
            }
        }
    }
}
