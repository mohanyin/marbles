import Foundation

/// Reads the current turn out of a session jsonl and keeps it up to date as the file grows.
///
/// Re-reading the whole file is not an option: sessions reach 12 MB and turns span a median of
/// 682 KB (max 2.5 MB observed), so the current turn's start can be megabytes from EOF. The model
/// is therefore: one bounded backward scan to find the turn boundary, then forward-only reads of
/// whatever bytes are new (PRD §7).
struct TranscriptReader {
    /// How far back to look for the turn boundary. 3× the largest span observed in a real
    /// session; one read of this size comes off the page cache in single-digit milliseconds.
    static let lookbackBudget = 8 * 1024 * 1024

    private(set) var parser = TranscriptParser()
    /// Byte offset already consumed. Always advances to EOF; partial lines live in the parser.
    private(set) var offset: UInt64 = 0

    var turn: TranscriptTurn { parser.turn }

    private init(parser: TranscriptParser, offset: UInt64) {
        self.parser = parser
        self.offset = offset
    }

    /// Cold start: locate the newest human turn and parse forward from it.
    static func load(path: String) -> TranscriptReader? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        guard size > 0 else { return TranscriptReader(parser: TranscriptParser(), offset: 0) }

        // Widen progressively rather than reading the whole budget up front: the boundary is
        // usually close to EOF (103 KB in a live 13 MB session), and reading 8 MB to find it
        // costs an order of magnitude more than reading 256 KB.
        var parser = TranscriptParser()
        var window = UInt64(min(Int(size), 256 * 1024))
        while true {
            let windowStart = size - window
            handle.seek(toFileOffset: windowStart)
            var data = handle.readDataToEndOfFile()

            // Drop the leading partial line unless the window reaches the start of the file.
            if windowStart > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                data = Data(data[(newline + 1)...])
            }

            if let start = turnStart(in: data) {
                parser.consume(Data(data[start...]))
                parser.flush()
                break
            }
            if window >= size || window >= UInt64(lookbackBudget) {
                // No boundary anywhere in the budget — show what we have and say it's partial.
                parser.consume(data)
                parser.flush()
                parser.markTruncated()
                break
            }
            window = min(window * 4, min(size, UInt64(lookbackBudget)))
            parser = TranscriptParser()
        }
        return TranscriptReader(parser: parser, offset: size)
    }

    /// Consume whatever has been appended since the last read. Returns true when the turn changed.
    mutating func refresh(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()

        if size < offset {
            // Truncated or replaced — start over.
            guard let fresh = TranscriptReader.load(path: path) else { return false }
            self = fresh
            return true
        }
        guard size > offset else { return false }

        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = size
        var changed = parser.consume(data)
        if parser.flush() { changed = true }
        return changed
    }

    /// Index of the first byte of the last line in `data` that opens a human turn.
    ///
    /// Walks backwards and stops at the first hit. Scanning forwards and keeping the last match
    /// costs a JSON parse per line across the whole window — 77 ms on a 13 MB session, a visible
    /// hitch on hover. The boundary is usually near the end, so backwards is typically a handful
    /// of lines.
    private static func turnStart(in data: Data) -> Data.Index? {
        var lineEnd = data.endIndex
        while lineEnd > data.startIndex {
            // Skip the newline terminating the previous line.
            var searchEnd = lineEnd
            if searchEnd > data.startIndex, data[searchEnd - 1] == UInt8(ascii: "\n") {
                searchEnd -= 1
            }
            guard searchEnd > data.startIndex else { break }
            let lineStart = data[data.startIndex..<searchEnd]
                .lastIndex(of: UInt8(ascii: "\n"))
                .map { $0 + 1 } ?? data.startIndex
            if TranscriptParser.isHumanTurn(line: Data(data[lineStart..<searchEnd])) {
                return lineStart
            }
            if lineStart == data.startIndex { break }
            lineEnd = lineStart
        }
        return nil
    }
}
