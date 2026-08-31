import AppKit

enum FocusCardMetricsTests {
    static func run() {
        alwaysIncludesOverhang()
        emptyPromptCollapsesRow()
        promptClampsAtMax()
        responseClampsAtMax()
        heightGrowsWithText()
        widthIsFixed()
        overflowOnlyWhenCapped()
        measuresTranscriptRuns()
    }

    private static func alwaysIncludesOverhang() {
        let bare = FocusCardMetrics.size(title: nil, prompt: nil, response: "")
        TestRun.expect(
            bare.height >= FocusCardMetrics.marbleDiameter + FocusCardMetrics.padding * 2,
            "empty card still reserves the whole marble"
        )
    }

    private static func emptyPromptCollapsesRow() {
        let withPrompt = FocusCardMetrics.size(title: "T", prompt: "hello", response: "reply")
        let without = FocusCardMetrics.size(title: "T", prompt: nil, response: "reply")
        TestRun.expect(without.height < withPrompt.height, "no prompt is a shorter card")
        TestRun.expectNear(FocusCardMetrics.promptHeight(nil), 0, "nil prompt has no height")
        TestRun.expectNear(FocusCardMetrics.promptHeight(""), 0, "empty prompt has no height")
    }

    private static func promptClampsAtMax() {
        let long = String(repeating: "prompt text ", count: 500)
        TestRun.expectNear(
            FocusCardMetrics.promptHeight(long),
            FocusCardMetrics.maxPromptHeight,
            "long prompt clamps to 72pt"
        )
    }

    private static func responseClampsAtMax() {
        let long = String(repeating: "response text ", count: 2000)
        TestRun.expectNear(
            FocusCardMetrics.responseHeight(long),
            FocusCardMetrics.maxTranscriptHeight,
            "long response clamps to 200pt"
        )
    }

    private static func heightGrowsWithText() {
        let short = FocusCardMetrics.size(title: "T", prompt: "hi", response: "one line")
        let tall = FocusCardMetrics.size(
            title: "T",
            prompt: "hi",
            response: String(repeating: "another line\n", count: 6)
        )
        TestRun.expect(tall.height > short.height, "more response means a taller card")

        let capped = FocusCardMetrics.size(
            title: "T",
            prompt: "hi",
            response: String(repeating: "another line\n", count: 400)
        )
        TestRun.expect(
            capped.height <= FocusCardMetrics.marbleDiameter
                + FocusCardMetrics.padding * 2
                + FocusCardMetrics.titleHeight
                + FocusCardMetrics.ruleHeight
                + FocusCardMetrics.gap * 3
                + FocusCardMetrics.maxPromptHeight
                + FocusCardMetrics.maxTranscriptHeight,
            "card never exceeds the sum of its caps"
        )
    }

    /// Drives whether a scroller is attached at all — AppKit flashes overlay scrollers on every
    /// document-size change, so a region that fits must never get one.
    private static func overflowOnlyWhenCapped() {
        TestRun.expect(!FocusCardMetrics.responseOverflows("Thinking…"), "one line does not overflow")
        TestRun.expect(!FocusCardMetrics.responseOverflows(""), "empty does not overflow")
        TestRun.expect(!FocusCardMetrics.promptOverflows(nil), "nil prompt does not overflow")
        TestRun.expect(!FocusCardMetrics.promptOverflows("fix the layout"), "short prompt does not overflow")

        let longReply = String(repeating: "a wrapping answer. ", count: 60)
        let longPrompt = String(repeating: "a long question. ", count: 30)
        TestRun.expect(FocusCardMetrics.responseOverflows(longReply), "long response overflows")
        TestRun.expect(FocusCardMetrics.promptOverflows(longPrompt), "long prompt overflows")

        // Overflow must agree with the height actually clamping.
        TestRun.expectNear(
            FocusCardMetrics.responseHeight(longReply),
            FocusCardMetrics.maxTranscriptHeight,
            "overflowing response sits at the cap"
        )
        TestRun.expectNear(
            FocusCardMetrics.promptHeight(longPrompt),
            FocusCardMetrics.maxPromptHeight,
            "overflowing prompt sits at the cap"
        )
        TestRun.expect(
            FocusCardMetrics.responseHeight("Thinking…") < FocusCardMetrics.maxTranscriptHeight,
            "non-overflowing response stays under the cap"
        )
    }

    /// Transcript geometry must match what `TranscriptView` lays out — the card's height is the
    /// sum of these, so any drift clips or leaves a gap.
    private static func measuresTranscriptRuns() {
        var turn = TranscriptTurn(prompt: "q")
        TestRun.expectNear(
            FocusCardMetrics.transcriptContentHeight(turn, fallback: "Thinking…"),
            FocusCardMetrics.textHeight("Thinking…", font: FocusCardMetrics.bodyFont,
                                        width: FocusCardMetrics.responseTextWidth),
            "empty turn measures the fallback line"
        )

        // A finished run collapses to one row; the newest running one expands.
        let done = TranscriptToolCall(id: "a", name: "Bash", target: "ls", status: .succeeded)
        let running = TranscriptToolCall(id: "b", name: "Bash", target: "ls", status: .running)
        TestRun.expectNear(
            FocusCardMetrics.runHeight(.tools([done, done, done]), isLast: false),
            FocusCardMetrics.toolRowHeight,
            "completed run collapses to a single row"
        )
        TestRun.expect(
            !FocusCardMetrics.runIsExpanded(.tools([done]), isLast: true),
            "a finished run stays collapsed even when newest"
        )
        TestRun.expect(
            FocusCardMetrics.runIsExpanded(.tools([done, running]), isLast: true),
            "the newest run expands while it is still working"
        )
        TestRun.expectNear(
            FocusCardMetrics.runHeight(.tools([done, running]), isLast: true),
            FocusCardMetrics.toolRowHeight * 2 + FocusCardMetrics.toolRowSpacing,
            "expanded run is one row per call"
        )

        // Spacing between runs is counted once per gap, not once per run.
        turn.entries = [.thinking, .thinking]
        TestRun.expectNear(
            FocusCardMetrics.transcriptContentHeight(turn, fallback: ""),
            FocusCardMetrics.thinkingRowHeight,
            "consecutive thinking collapses to one run"
        )
        turn.entries = [.thinking, .prose("hello"), .thinking]
        let expected = FocusCardMetrics.thinkingRowHeight * 2
            + FocusCardMetrics.textHeight("hello", font: FocusCardMetrics.bodyFont,
                                          width: FocusCardMetrics.responseTextWidth)
            + FocusCardMetrics.runSpacing * 2
        TestRun.expectNear(
            FocusCardMetrics.transcriptContentHeight(turn, fallback: ""),
            expected,
            "three runs means two gaps"
        )

        // And it clamps.
        turn.entries = (0..<200).map { .prose("line \($0)") }
        TestRun.expectNear(
            FocusCardMetrics.transcriptHeight(turn, fallback: ""),
            FocusCardMetrics.maxTranscriptHeight,
            "long transcript clamps to the cap"
        )
        TestRun.expect(
            FocusCardMetrics.transcriptOverflows(turn, fallback: ""),
            "clamped transcript reports overflow"
        )
    }

    private static func widthIsFixed() {
        let a = FocusCardMetrics.size(title: "T", prompt: "hi", response: "there")
        let b = FocusCardMetrics.size(title: nil, prompt: nil, response: "")
        TestRun.expectNear(a.width, FocusCardMetrics.width, "width is the metrics constant")
        TestRun.expectNear(b.width, FocusCardMetrics.width, "empty card keeps the width")
        TestRun.expectNear(a.width, LayoutEngine.focusCardWidth, "metrics and layout agree on width")
    }
}
