import AppKit

@MainActor
final class QuickLinkFocusHighlight: NSView {
    private var pulse: QueryTransitionAnimation?
    private(set) var targetFrame: NSRect?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 2
        layer?.zPosition = 1
        layer?.masksToBounds = false
        layer?.shadowRadius = 4
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 0
        alphaValue = 0
        setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.shadowColor = NSColor.controlAccentColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func move(to rect: NSRect?, duration: TimeInterval) {
        guard targetFrame != rect else { return }
        pulse?.stop()
        pulse = nil
        setGlow(0)
        targetFrame = rect
        alphaValue = rect == nil ? 0 : 1
        guard let rect else { return }
        frame = rect
        guard duration > 0 else { return }
        let animation = QueryTransitionAnimation(duration: duration) { [weak self] progress in
            let intensity = max(0, min(progress * 4, (1 - progress) / 0.75))
            self?.setGlow(Float(intensity) * 0.7)
        }
        pulse = animation
        animation.start()
    }

    private func setGlow(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowOpacity = opacity
        CATransaction.commit()
    }

    func reset() {
        pulse?.stop()
        pulse = nil
        setGlow(0)
        targetFrame = nil
        alphaValue = 0
    }

}

@MainActor
final class QuickLinkQueryBar: NSScrollView, NSTextFieldDelegate {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onReturnToSearch: (() -> Void)?
    var onFocusChange: (() -> Void)?
    let focusHighlight = QuickLinkFocusHighlight(frame: .zero)
    private let content = NSStackView()
    private var link: QuickLink?
    private var fields: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        documentView = content
        content.addSubview(focusHighlight)
        content.heightAnchor.constraint(equalTo: contentView.heightAnchor).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        setAccessibilityLabel("Quick link queries")
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private var focusedIndex: Int? { fields.firstIndex { $0.currentEditor() != nil } }
    var isEditing: Bool { focusedIndex != nil }
    var escapeTitle: String { focusedIndex == 0 ? "Search" : "Previous query" }

    func moveLeft() {
        guard let index = focusedIndex else { return }
        if index == 0 {
            onReturnToSearch?()
            // The deferred editing notification may not run inside a nested event loop.
            // Reflect the new focus as soon as the return-to-search action finishes.
            updateFocusHighlight(fields.first { $0.currentEditor() != nil })
        } else {
            focus(fields[index - 1])
        }
    }

    var values: [String: String] {
        Dictionary(uniqueKeysWithValues: zip(link?.arguments ?? [], fields).map { ($0.token, $1.stringValue) })
    }

    func configure(link: QuickLink?) {
        guard self.link != link else { return }
        self.link = link
        focusHighlight.reset()
        content.arrangedSubviews.forEach {
            content.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        fields = (link?.arguments ?? []).map(makeField)
        fields.forEach { content.addArrangedSubview($0) }
        isHidden = fields.isEmpty
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    private func makeField(_ argument: QuickLink.Argument) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = argument.name
        field.setAccessibilityLabel(argument.name)
        field.setAccessibilityIdentifier("quickLinkQuery:" + argument.token)
        field.toolTip = argument.name
        field.font = .systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return field
    }

    @discardableResult
    func focusFirst() -> Bool {
        guard let field = fields.first else { return false }
        focus(field)
        return true
    }

    @discardableResult
    func focusFirstMissing() -> Bool {
        guard let field = fields.first(where: { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }
        focus(field)
        return true
    }

    private func focus(_ field: NSTextField) {
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(field)
        field.selectText(nil)
        layoutSubtreeIfNeeded()
        field.scrollToVisible(field.bounds.insetBy(dx: -4, dy: 0))
        updateFocusHighlight(field)
        onFocusChange?()
    }

    private func updateFocusHighlight(_ activeField: NSTextField?) {
        content.layoutSubtreeIfNeeded()
        if content.subviews.last !== focusHighlight {
            content.addSubview(focusHighlight, positioned: .above, relativeTo: nil)
        }
        let rect = activeField.map { content.convert($0.bounds, from: $0) }
        focusHighlight.move(to: rect, duration: Appearance.launcherTransitionDuration(for: window))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFocusHighlight(fields.first { $0.currentEditor() != nil })
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        updateFocusHighlight(obj.object as? NSTextField)
        onFocusChange?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // A new query can begin editing synchronously; let it keep the existing outline.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateFocusHighlight(self.fields.first { $0.currentEditor() != nil })
        }
    }

    func restoreValues(_ values: [String: String]) {
        for (argument, field) in zip(link?.arguments ?? [], fields) {
            field.stringValue = values[argument.token] ?? ""
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText(),
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control]).isEmpty != false,
              let index = fields.firstIndex(where: { $0 === control }) else { return false }
        let commands: [Selector: () -> Void] = [
            #selector(NSResponder.insertTab(_:)): { self.focus(self.fields[(index + 1) % self.fields.count]) },
            #selector(NSResponder.insertBacktab(_:)): { self.focusPrevious(before: index) },
            #selector(NSResponder.insertNewline(_:)): { self.onSubmit?() },
            #selector(NSResponder.cancelOperation(_:)): { self.onEscape?() }
        ]
        guard let command = commands[selector] else { return false }
        if NSApp.currentEvent?.isARepeat != true { command() }
        return true
    }

    private func focusPrevious(before index: Int) {
        focus(fields[(index + fields.count - 1) % fields.count])
    }
}

@MainActor
enum QuickLinkOpener {
    static func open(_ link: QuickLink, url: URL, completion: @escaping (Error?) -> Void) {
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            completion(QuickLinkError.missingFile)
            return
        }
        if let applicationURL = link.applicationURL {
            NSWorkspace.shared.open([url], withApplicationAt: applicationURL,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                Task { @MainActor in completion(error) }
            }
        } else {
            let opened = NSWorkspace.shared.open(url)
            completion(opened ? nil : NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError,
                                             userInfo: [NSLocalizedDescriptionKey: "No application could open this quick link."]))
        }
    }
}
