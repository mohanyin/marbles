import AppKit

final class FocusCardView: NSView {
    static let size = LayoutEngine.focusCardSize

    var onJump: ((JumpKind) -> Void)?

    private let backdrop = NSVisualEffectView()
    private let title = NSTextField(labelWithString: "")
    private let previewScroll = NSScrollView()
    private let preview = NSTextView()
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

        claudeButton.target = self
        claudeButton.action = #selector(jumpClaude)
        cursorButton.target = self
        cursorButton.action = #selector(jumpCursor)
        terminalButton.target = self
        terminalButton.action = #selector(jumpTerminal)
        conductorButton.target = self
        conductorButton.action = #selector(jumpConductor)

        for button in [claudeButton, cursorButton, terminalButton, conductorButton] {
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(agent: Agent, launcher: AppLaunching = WorkspaceLauncher.shared) {
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
        apply(claudeButton, JumpRouter.decision(.claudeCode, agent: agent, launcher: launcher))
        apply(cursorButton, JumpRouter.decision(.cursor, agent: agent, launcher: launcher))
        apply(terminalButton, JumpRouter.decision(.terminal, agent: agent, launcher: launcher))
        apply(conductorButton, JumpRouter.decision(.conductor, agent: agent, launcher: launcher))
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

        var buttonX = pad
        var buttonY = y + previewHeight + 12
        let maxX = bounds.width - pad
        for button in [claudeButton, cursorButton, terminalButton, conductorButton] where !button.isHidden {
            button.sizeToFit()
            let width = ceil(button.fittingSize.width + 8)
            if buttonX > pad, buttonX + width > maxX {
                buttonX = pad
                buttonY += 28
            }
            button.frame = NSRect(x: buttonX, y: buttonY, width: width, height: 24)
            buttonX += width + 6
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? self
    }

    @objc private func jumpClaude() { onJump?(.claudeCode) }
    @objc private func jumpCursor() { onJump?(.cursor) }
    @objc private func jumpTerminal() { onJump?(.terminal) }
    @objc private func jumpConductor() { onJump?(.conductor) }

    private func apply(_ button: NSButton, _ decision: JumpDecision) {
        button.isHidden = !decision.visible
        button.isEnabled = decision.enabled
        button.toolTip = decision.tooltip
    }

    private static func makeAction(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .flexiblePush
        button.controlSize = .small
        return button
    }
}
