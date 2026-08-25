import AppKit

final class FocusCardView: NSView {
    static let size = LayoutEngine.focusCardSize

    private let backdrop = NSVisualEffectView()
    private let title = NSTextField(labelWithString: "")
    private let previewScroll = NSScrollView()
    private let preview = NSTextView()
    private let reply = NSTextField(labelWithString: "Reply isn’t available yet.")
    private var chipViews: [ChipView] = []
    private let claudeButton = FocusCardView.makeAction("Open Claude Code")
    private let cursorButton = FocusCardView.makeAction("Open Cursor")
    private let terminalButton = FocusCardView.makeAction("Open Terminal")
    private let conductorButton = FocusCardView.makeAction("Open Conductor")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        addSubview(backdrop)

        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        addSubview(title)

        previewScroll.hasVerticalScroller = true
        previewScroll.hasHorizontalScroller = false
        previewScroll.autohidesScrollers = true
        previewScroll.drawsBackground = false
        previewScroll.borderType = .noBorder
        previewScroll.scrollerStyle = .overlay
        previewScroll.documentView = preview
        addSubview(previewScroll)

        preview.isEditable = false
        preview.isSelectable = true
        preview.isRichText = false
        preview.drawsBackground = false
        preview.font = NSFont.systemFont(ofSize: 13)
        preview.textColor = .labelColor
        preview.textContainerInset = .zero
        preview.textContainer?.lineFragmentPadding = 0
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        preview.textContainer?.widthTracksTextView = true
        preview.minSize = NSSize(width: 0, height: 0)
        preview.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        reply.font = NSFont.systemFont(ofSize: 11)
        reply.textColor = .secondaryLabelColor
        addSubview(reply)

        for button in [claudeButton, cursorButton, terminalButton, conductorButton] {
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(agent: Agent) {
        if let heading = FocusPreview.title(for: agent) {
            title.stringValue = heading
            title.isHidden = false
        } else {
            title.stringValue = ""
            title.isHidden = true
        }
        let next = FocusPreview.line(for: agent)
        if preview.string != next {
            preview.string = next
            preview.scrollToBeginningOfDocument(nil)
        }
        let actions = FocusPreview.actions(for: agent)
        claudeButton.isHidden = !actions.showClaudeCode
        cursorButton.isHidden = !actions.showCursor
        terminalButton.isHidden = !actions.showTerminal
        conductorButton.isHidden = !actions.showConductor
        syncChips(Chips.focusChips(for: agent))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        let pad: CGFloat = 14
        let width = bounds.width - pad * 2
        var y = pad
        if !title.isHidden {
            title.frame = NSRect(x: pad, y: y, width: width, height: 18)
            y += 22
        }
        let previewHeight: CGFloat = title.isHidden ? 182 : 160
        previewScroll.frame = NSRect(x: pad, y: y, width: width, height: previewHeight)
        let inner = max(previewScroll.contentSize.width, 1)
        preview.minSize = NSSize(width: inner, height: 0)
        preview.maxSize = NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude)
        preview.textContainer?.containerSize = NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude)
        preview.frame.size.width = inner

        var x = pad
        let chipY = y + previewHeight + 10
        let chip: CGFloat = 22
        for view in chipViews {
            view.frame = NSRect(x: x, y: chipY, width: chip, height: chip)
            x += chip + 6
        }

        var buttonX = pad
        let buttonY = chipY + chip + 12
        for button in [claudeButton, cursorButton, terminalButton, conductorButton] where !button.isHidden {
            button.sizeToFit()
            let size = button.fittingSize
            button.frame = NSRect(x: buttonX, y: buttonY, width: ceil(size.width + 8), height: 24)
            buttonX += button.frame.width + 6
        }

        reply.frame = NSRect(x: pad, y: buttonY + 32, width: width, height: 16)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? self
    }

    private func syncChips(_ kinds: [ChipKind]) {
        while chipViews.count < kinds.count {
            let view = ChipView(frame: .zero)
            chipViews.append(view)
            addSubview(view)
        }
        while chipViews.count > kinds.count {
            chipViews.removeLast().removeFromSuperview()
        }
        for (view, kind) in zip(chipViews, kinds) {
            view.kind = kind
            view.fade = 1
        }
    }

    private static func makeAction(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .flexiblePush
        button.controlSize = .small
        button.isEnabled = false
        button.toolTip = "Jump-in lands in the next update"
        return button
    }
}
