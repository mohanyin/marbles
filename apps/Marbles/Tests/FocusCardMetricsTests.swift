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
            FocusCardMetrics.maxResponseHeight,
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
                + FocusCardMetrics.maxResponseHeight,
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
            FocusCardMetrics.maxResponseHeight,
            "overflowing response sits at the cap"
        )
        TestRun.expectNear(
            FocusCardMetrics.promptHeight(longPrompt),
            FocusCardMetrics.maxPromptHeight,
            "overflowing prompt sits at the cap"
        )
        TestRun.expect(
            FocusCardMetrics.responseHeight("Thinking…") < FocusCardMetrics.maxResponseHeight,
            "non-overflowing response stays under the cap"
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
