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

final class TranslationSkeletonView: NSStackView {
    init(fillColor: NSColor = .quaternaryLabelColor) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 14
        wantsLayer = true
        setAccessibilityHidden(true)
        for width: CGFloat in [0.94, 0.81, 0.58] {
            let line = AppearanceSurfaceView(fillColor: fillColor)
            line.layer?.cornerRadius = 6
            addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: widthAnchor, multiplier: width).isActive = true
            line.heightAnchor.constraint(equalToConstant: 12).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(fillColor:)") }

    override func viewDidHide() {
        super.viewDidHide()
        setLoading(false)
    }

    func setLoading(_ loading: Bool) {
        guard loading, !isHidden, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layer?.removeAnimation(forKey: "translationSkeletonPulse")
            return
        }
        guard layer?.animation(forKey: "translationSkeletonPulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.2
        pulse.duration = 0.55
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer?.add(pulse, forKey: "translationSkeletonPulse")
    }
}

final class TranslationCandidatePreviewView: ResultPreviewStripView {
    private let languageLabel = Appearance.label("", size: 13, weight: .medium, color: .labelColor)
    private let skeleton = TranslationSkeletonView(fillColor: .tertiaryLabelColor)
    private let output = NSTextField(wrappingLabelWithString: "")
    private(set) var language: TranslationLanguage?
    private(set) var response: TranslationResponse?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = 0.4
        output.font = .systemFont(ofSize: 21)
        output.textColor = .labelColor
        output.maximumNumberOfLines = 6
        output.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for child in [languageLabel, skeleton, output] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            languageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            languageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            languageLabel.topAnchor.constraint(equalTo: topAnchor),
            skeleton.leadingAnchor.constraint(equalTo: leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: languageLabel.trailingAnchor),
            skeleton.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 22),
            output.leadingAnchor.constraint(equalTo: skeleton.leadingAnchor),
            output.trailingAnchor.constraint(equalTo: skeleton.trailingAnchor),
            output.topAnchor.constraint(equalTo: skeleton.topAnchor),
            output.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ language: TranslationLanguage?, response: TranslationResponse?) {
        self.language = language
        self.response = response
        isHidden = language == nil
        languageLabel.stringValue = language?.rawValue ?? ""
        skeleton.isHidden = response != nil
        output.isHidden = response == nil
        output.stringValue = response?.text ?? ""
        output.toolTip = response?.text
        setAccessibilityLabel(language.map { "Next target language: \($0.rawValue)" })
    }
}

final class TranslationResultView: NSView {
    private let primary = NSView()
    private let nextCandidate = TranslationCandidatePreviewView()
    private let skeleton = TranslationSkeletonView()
    private lazy var fullWidth = primary.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
    private lazy var previewWidth = primary.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.66, constant: -42)
    private let heading = Appearance.label("", size: 13, weight: .medium, color: .secondaryLabelColor)
    private let detail = Appearance.label("", size: 16, color: .secondaryLabelColor)
    private let progress = NSProgressIndicator()
    private let output = TranslationTextView()
    private let scroll = NSScrollView()
    private var previousQuery: TranslationQuery?
    private var previousLanguage: TranslationLanguage?
    private var renderedResponse: TranslationResponse?
    var onExit: (() -> Void)? { didSet { output.onExit = onExit } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        primary.wantsLayer = true
        primary.layer?.masksToBounds = true
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
        for child in [primary, nextCandidate] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        [header, detail, scroll, skeleton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            primary.addSubview($0)
        }
        NSLayoutConstraint.activate([
            primary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            primary.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            primary.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            fullWidth,
            nextCandidate.leadingAnchor.constraint(equalTo: primary.trailingAnchor, constant: 32),
            nextCandidate.trailingAnchor.constraint(equalTo: trailingAnchor),
            nextCandidate.topAnchor.constraint(equalTo: primary.topAnchor),
            nextCandidate.bottomAnchor.constraint(equalTo: primary.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: primary.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: primary.trailingAnchor),
            header.topAnchor.constraint(equalTo: primary.topAnchor),
            detail.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            detail.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 22),
            scroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: detail.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: primary.bottomAnchor),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: primary.bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            skeleton.topAnchor.constraint(equalTo: detail.topAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ session: TranslationSession, preferences: TranslationPreferences, direction: Int = 0) {
        let inputChanged = previousQuery != session.query
        let switched = previousLanguage != nil && previousLanguage != session.language && !inputChanged
        if inputChanged { clearSwitchAnimations() }
        configureCandidate(session, preferences: preferences)
        configureResult(session)
        if switched {
            let offset = direction == 0 ? inferredDirection(preferences, session: session) : direction
            animateSwitch(direction: offset)
        }
        previousQuery = session.query
        previousLanguage = session.language
    }

    private func configureCandidate(_ session: TranslationSession, preferences: TranslationPreferences) {
        let source = session.sourceLanguage
        let next = preferences.availableTargets(excluding: source).count > 1
            ? preferences.targetLanguage(shiftedBy: 1, excluding: source, from: session.language) : nil
        nextCandidate.configure(next, response: next.flatMap { session.cachedResponse(for: $0) })
        if fullWidth.isActive != (next == nil) {
            NSLayoutConstraint.deactivate([fullWidth, previewWidth])
            (next == nil ? fullWidth : previewWidth).isActive = true
        }
    }

    private func configureResult(_ session: TranslationSession) {
        let source = session.sourceLanguage?.displayName ?? "Auto-detect"
        heading.stringValue = "\(source) → \(session.language.rawValue) · DeepSeek"
        heading.toolTip = sourceLanguageHelp(session.sourceLanguage)
        configureOutput(session.cachedResponse(for: session.language))
        scroll.isHidden = session.state.answer == nil
        let showsSkeleton = session.state == .ready || session.state == .waiting || session.state == .loading
        skeleton.isHidden = !showsSkeleton
        skeleton.setLoading(session.state == .loading)
        detail.isHidden = session.state.answer != nil || showsSkeleton
        detail.textColor = .secondaryLabelColor
        progress.stopAnimation(nil)
        detail.stringValue = ""
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

    private func configureOutput(_ response: TranslationResponse?) {
        guard renderedResponse != response else { return }
        renderedResponse = response
        let text = NSMutableAttributedString(string: response?.text ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 21), .foregroundColor: NSColor.labelColor
        ])
        if let explanation = response?.explanation {
            appendSection("Meaning", body: explanation, to: text)
        }
        if let meanings = response?.alternateMeanings, !meanings.isEmpty {
            let list = meanings.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
            appendSection("Other meanings", body: list, to: text)
        }
        output.textStorage?.setAttributedString(text)
        output.scrollToBeginningOfDocument(nil)
    }

    private func appendSection(_ title: String, body: String, to text: NSMutableAttributedString) {
        text.append(NSAttributedString(string: "\n\n\(title)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        text.append(NSAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]))
    }

    private func inferredDirection(_ preferences: TranslationPreferences, session: TranslationSession) -> Int {
        preferences.targetLanguage(shiftedBy: -1, excluding: session.sourceLanguage,
                                   from: session.language) == previousLanguage ? 1 : -1
    }

    private func clearSwitchAnimations() {
        for card in [primary, nextCandidate] {
            card.layer?.removeAnimation(forKey: "transition")
            card.layer?.removeAnimation(forKey: "translationSwitchOpacity")
        }
    }

    private func animateSwitch(direction: Int) {
        let duration = Appearance.launcherTransitionDuration(for: window)
        guard duration > 0 else { clearSwitchAnimations(); return }
        for (card, from, to) in [(primary, Float(0.4), Float(1)), (nextCandidate, Float(1), Float(0.4))] {
            let opacity = card.layer?.animation(forKey: "translationSwitchOpacity") == nil
                ? from : (card.layer?.presentation()?.opacity ?? from)
            let slide = CATransition()
            slide.type = .push
            slide.subtype = direction > 0 ? .fromRight : .fromLeft
            slide.duration = duration
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            card.layer?.add(slide, forKey: "transition")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity
            fade.toValue = to
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            card.layer?.add(fade, forKey: "translationSwitchOpacity")
        }
    }

    private func sourceLanguageHelp(_ language: InferredSourceLanguage?) -> String {
        guard let language else { return "The source language will be inferred when enough text is available." }
        return language.origin == .deepSeek ? "Source language inferred by DeepSeek." : "Source language inferred on this Mac."
    }
}
