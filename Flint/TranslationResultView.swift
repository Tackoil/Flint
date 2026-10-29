import AppKit

private final class TranslationTextView: NSTextView {
    var onExit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?(); return }
        // The footer's shared Return hint runs the copy action on key release.
        if [36, 76].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty { return }
        super.keyDown(with: event)
    }
}

final class TranslationResultView: NSView {
    private let heading = Appearance.label("", size: 13, weight: .medium, color: .secondaryLabelColor)
    private let detail = Appearance.label("", size: 16, color: .secondaryLabelColor)
    private let progress = NSProgressIndicator()
    private let output = TranslationTextView()
    private let scroll = NSScrollView()
    var onExit: (() -> Void)? { didSet { output.onExit = onExit } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        detail.maximumNumberOfLines = 0
        detail.lineBreakMode = .byWordWrapping
        detail.cell?.usesSingleLineMode = false
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        output.isEditable = false
        output.isSelectable = true
        output.isRichText = false
        output.drawsBackground = false
        output.font = .systemFont(ofSize: 21)
        output.textColor = .labelColor
        output.textContainerInset = .zero
        output.textContainer?.lineFragmentPadding = 0
        output.textContainer?.widthTracksTextView = true
        output.isHorizontallyResizable = false
        output.isVerticallyResizable = true
        output.autoresizingMask = [.width]
        output.setAccessibilityLabel("Translation result")
        scroll.documentView = output
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let header = Appearance.stack([heading, Appearance.spacer(), progress], spacing: 12)
        [header, detail, scroll].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            detail.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            detail.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 22),
            scroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: detail.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ session: TranslationSession) {
        heading.stringValue = "Auto-detect → \(session.language.rawValue) · DeepSeek"
        let answer = session.state.answer ?? ""
        if output.string != answer {
            output.string = answer
            output.scrollToBeginningOfDocument(nil)
        }
        scroll.isHidden = session.state.answer == nil
        detail.isHidden = session.state.answer != nil
        detail.textColor = .secondaryLabelColor
        progress.stopAnimation(nil)
        detail.stringValue = "Type or paste text above. Translation starts automatically after a short pause.\nEscape returns to search."
        if session.state == .waiting { detail.stringValue = "Waiting for you to finish typing…" }
        if session.state == .loading {
            detail.stringValue = "Translating…"
            progress.startAnimation(nil)
        }
        if session.state == .needsAPIKey {
            detail.stringValue = "Add or update your DeepSeek API key in Translation Settings to continue."
        }
        if case .failed(let message) = session.state {
            detail.stringValue = message
            detail.textColor = .systemRed
        }
    }
}
