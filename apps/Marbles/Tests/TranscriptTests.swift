import Foundation

enum TranscriptTests {
    static func run() {
        parsesAssistantProse()
        parsesToolCallsAndResolvesStatus()
        bashTargetSkipsDirectoryHops()
        failedToolResultMarksFailure()
        newHumanTurnResetsTheStream()
        toolResultsDoNotOpenATurn()
        skipsScaffoldingAndSidechains()
        collapsesThinking()
        groupsToolRuns()
        handlesSplitWrites()
        enforcesEntryCap()
        readerFindsTurnBoundary()
        readerAppendsIncrementally()
        readerRestartsOnTruncation()
    }

    // MARK: - Fixtures

    private static func human(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
    }

    private static func prose(_ text: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    private static func toolUse(_ id: String, _ name: String, _ input: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
    }

    private static func toolResult(_ id: String, error: Bool = false) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"output","is_error":\#(error)}]}}"#
    }

    private static func parse(_ lines: [String]) -> TranscriptTurn {
        var parser = TranscriptParser()
        parser.consume(Data((lines.joined(separator: "\n") + "\n").utf8))
        return parser.turn
    }

    // MARK: - Parsing

    private static func parsesAssistantProse() {
        let turn = parse([human("do the thing"), prose("On it."), prose("Done.")])
        TestRun.expectEqual(turn.prompt, "do the thing", "prompt captured")
        TestRun.expectEqual(turn.entries.count, 2, "two prose entries")
        if case .prose(let first) = turn.entries.first {
            TestRun.expectEqual(first, "On it.", "first prose text")
        } else {
            TestRun.expect(false, "first entry is prose")
        }
    }

    private static func parsesToolCallsAndResolvesStatus() {
        let turn = parse([
            human("run the tests"),
            toolUse("t1", "Bash", #"{"command":"./scripts/test.sh"}"#),
            toolResult("t1"),
        ])
        guard case .tool(let call) = turn.entries.first else {
            TestRun.expect(false, "first entry is a tool call")
            return
        }
        TestRun.expectEqual(call.name, "Bash", "tool name")
        TestRun.expectEqual(call.target, "./scripts/test.sh", "target from command")
        TestRun.expect(call.status == .succeeded, "resolved to succeeded")
        TestRun.expectEqual(call.label, "Bash ./scripts/test.sh", "row label")
    }

    /// Agent commands nearly always start with a `cd`, which would otherwise fill the row.
    private static func bashTargetSkipsDirectoryHops() {
        let turn = parse([
            human("q"),
            toolUse("t1", "Bash", #"{"command":"./scripts/test.sh"}"#),
        ])
        guard case .tool(let call) = turn.entries.first else {
            TestRun.expect(false, "tool entry present")
            return
        }
        TestRun.expectEqual(call.target, "./scripts/test.sh", "leading cd hop dropped")

        let multi = parse([
            human("q"),
            toolUse("t2", "Bash", #"{"command":"cd /a && cd /b && git status --short"}"#),
        ])
        if case .tool(let call) = multi.entries.first {
            TestRun.expectEqual(call.target, "git status --short", "repeated hops dropped")
        }

        let plain = parse([human("q"), toolUse("t3", "Bash", #"{"command":"ls -la"}"#)])
        if case .tool(let call) = plain.entries.first {
            TestRun.expectEqual(call.target, "ls -la", "commands without a hop are untouched")
        }
    }

    private static func failedToolResultMarksFailure() {
        let turn = parse([
            human("q"),
            toolUse("t1", "Read", #"{"file_path":"/a/b/FocusCardView.swift"}"#),
            toolResult("t1", error: true),
        ])
        guard case .tool(let call) = turn.entries.first else {
            TestRun.expect(false, "tool entry present")
            return
        }
        TestRun.expect(call.status == .failed, "is_error marks the row failed")
        TestRun.expectEqual(call.target, "FocusCardView.swift", "target is the basename")
    }

    private static func newHumanTurnResetsTheStream() {
        let turn = parse([
            human("first question"),
            prose("first answer"),
            toolUse("t1", "Bash", #"{"command":"ls"}"#),
            human("second question"),
            prose("second answer"),
        ])
        TestRun.expectEqual(turn.prompt, "second question", "prompt is the newest turn")
        TestRun.expectEqual(turn.entries.count, 1, "earlier turn discarded")
        if case .prose(let text) = turn.entries.first {
            TestRun.expectEqual(text, "second answer", "only the new turn's prose survives")
        }
    }

    private static func toolResultsDoNotOpenATurn() {
        let turn = parse([
            human("the real question"),
            toolUse("t1", "Bash", #"{"command":"ls"}"#),
            toolResult("t1"),
            prose("after the tool"),
        ])
        TestRun.expectEqual(turn.prompt, "the real question", "tool_result is not a human turn")
        TestRun.expectEqual(turn.entries.count, 2, "tool row plus prose")
    }

    private static func skipsScaffoldingAndSidechains() {
        let noise = [
            #"{"type":"attachment","attachment":{"type":"edited_text_file"}}"#,
            #"{"type":"system","subtype":"hook","hookCount":2}"#,
            #"{"type":"queue-operation"}"#,
            #"{"type":"custom-title","customTitle":"Some title"}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent chatter"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"<system-reminder>ignore me</system-reminder>"}}"#,
        ]
        let turn = parse([human("q")] + noise + [prose("real answer")])
        TestRun.expectEqual(turn.prompt, "q", "scaffolding does not replace the prompt")
        TestRun.expectEqual(turn.entries.count, 1, "only the real assistant text survives")
    }

    private static func collapsesThinking() {
        let think = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"","signature":"abc"}]}}"#
        let turn = parse([human("q"), think, think, think, prose("answer")])
        TestRun.expectEqual(turn.entries.count, 4, "each thinking block is an entry")
        let runs = turn.runs
        TestRun.expectEqual(runs.count, 2, "consecutive thinking collapses to one run")
        if case .thinking = runs.first {} else { TestRun.expect(false, "first run is thinking") }
    }

    private static func groupsToolRuns() {
        let turn = parse([
            human("q"),
            toolUse("t1", "Bash", #"{"command":"a"}"#),
            toolUse("t2", "Bash", #"{"command":"b"}"#),
            toolUse("t3", "Bash", #"{"command":"c"}"#),
            prose("interrupted by prose"),
            toolUse("t4", "Bash", #"{"command":"d"}"#),
        ])
        let runs = turn.runs
        TestRun.expectEqual(runs.count, 3, "tools, prose, tools")
        if case .tools(let first) = runs.first {
            TestRun.expectEqual(first.count, 3, "first run holds three calls")
        } else {
            TestRun.expect(false, "first run is a tool run")
        }
        if case .tools(let last) = runs.last {
            TestRun.expectEqual(last.count, 1, "prose breaks the run")
        } else {
            TestRun.expect(false, "last run is a tool run")
        }
    }

    /// The reader appends whatever bytes are new, which can split a line anywhere.
    private static func handlesSplitWrites() {
        let full = ([human("q"), prose("hello there"), prose("second")]
            .joined(separator: "\n") + "\n")
        let bytes = Array(full.utf8)
        var parser = TranscriptParser()
        // Feed one byte at a time — the worst case for partial-line handling.
        for byte in bytes {
            parser.consume(Data([byte]))
        }
        TestRun.expectEqual(parser.turn.prompt, "q", "prompt survives byte-wise feeding")
        TestRun.expectEqual(parser.turn.entries.count, 2, "both prose entries parsed")
    }

    private static func enforcesEntryCap() {
        var lines = [human("q")]
        for index in 0..<(TranscriptParser.maxEntries + 50) {
            lines.append(toolUse("t\(index)", "Bash", #"{"command":"x"}"#))
        }
        let turn = parse(lines)
        TestRun.expectEqual(turn.entries.count, TranscriptParser.maxEntries, "entries capped")
        TestRun.expect(turn.truncatedAtTop, "cap marks the stream truncated")
    }

    // MARK: - Reader

    private static func tempFile(_ contents: String) -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marbles-transcript-\(UUID().uuidString).jsonl")
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// The boundary can be far from EOF — a real session showed 2.5 MB between turns. The
    /// filler here exceeds the reader's initial 256 KB window, so this also covers the
    /// progressive widening path.
    private static func readerFindsTurnBoundary() {
        var lines = [human("old question")]
        for index in 0..<1_500 {
            lines.append(prose(String(repeating: "filler ", count: 60) + "\(index)"))
        }
        lines.append(human("current question"))
        lines.append(prose("current answer"))
        let path = tempFile(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        guard let reader = TranscriptReader.load(path: path) else {
            TestRun.expect(false, "reader loaded")
            return
        }
        TestRun.expectEqual(reader.turn.prompt, "current question", "found the newest boundary")
        TestRun.expectEqual(reader.turn.entries.count, 1, "earlier turn not parsed")
    }

    private static func readerAppendsIncrementally() {
        let path = tempFile([human("q"), prose("one")].joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard var reader = TranscriptReader.load(path: path) else {
            TestRun.expect(false, "reader loaded")
            return
        }
        let before = reader.offset
        TestRun.expectEqual(reader.turn.entries.count, 1, "one entry to start")
        TestRun.expect(!reader.refresh(path: path), "no change when the file is untouched")

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data((prose("two") + "\n").utf8))
            try? handle.close()
        }
        TestRun.expect(reader.refresh(path: path), "refresh reports the change")
        TestRun.expectEqual(reader.turn.entries.count, 2, "appended entry parsed")
        TestRun.expect(reader.offset > before, "offset advanced")
    }

    private static func readerRestartsOnTruncation() {
        let path = tempFile([human("q"), prose("one"), prose("two")].joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard var reader = TranscriptReader.load(path: path) else {
            TestRun.expect(false, "reader loaded")
            return
        }
        TestRun.expectEqual(reader.turn.entries.count, 2, "two entries before rotation")

        // File replaced by a shorter one — the session was cleared.
        try? ([human("fresh"), prose("new")].joined(separator: "\n") + "\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
        TestRun.expect(reader.refresh(path: path), "shrinking file forces a reload")
        TestRun.expectEqual(reader.turn.prompt, "fresh", "restarted from the new content")
        TestRun.expectEqual(reader.turn.entries.count, 1, "new turn only")
    }
}
