import Foundation

/// Watches one session jsonl and reports writes.
///
/// Only ever alive while a Focus card is open on that agent (PRD §7) — the rest of the time the
/// hook stream is refresh enough, and a watcher per live agent would be a file descriptor each for
/// no benefit.
///
/// Writes are coalesced: an agent streaming a reply can touch the file many times a second, and
/// each notification costs a parse plus a card rebuild.
@MainActor
final class TranscriptWatcher {
    /// Long enough to swallow a burst mid-write, short enough to still feel live.
    static let coalesceInterval: TimeInterval = 0.08

    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: Timer?

    init?(path: String, onChange: @escaping () -> Void) {
        guard !path.isEmpty else { return nil }
        self.path = path
        self.onChange = onChange
        guard start() else { return nil }
    }

    deinit {
        source?.cancel()
    }

    func stop() {
        pending?.invalidate()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func start() -> Bool {
        descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // The session file was replaced; re-open against the new inode.
                self.restart()
                return
            }
            self.schedule()
        }
        let descriptor = self.descriptor
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    private func restart() {
        stop()
        _ = start()
        schedule()
    }

    private func schedule() {
        guard pending == nil else { return }
        pending = Timer.scheduledTimer(withTimeInterval: Self.coalesceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pending = nil
                self.onChange()
            }
        }
    }
}
