import AppKit

enum KeyboardHint: Equatable {
    case returnKey, escape, upArrow, downArrow, leftArrow, rightArrow, command
    case text(String)

    static let pointSize: CGFloat = 11
    static let keycapSize: CGFloat = 22
    static let labelSpacing: CGFloat = 8
    private static var symbolConfiguration: NSImage.SymbolConfiguration {
        .init(pointSize: pointSize, weight: .regular)
    }

    var name: String {
        switch self {
        case .returnKey: return "Return"
        case .escape: return "Escape"
        case .upArrow: return "Up Arrow"
        case .downArrow: return "Down Arrow"
        case .leftArrow: return "Left Arrow"
        case .rightArrow: return "Right Arrow"
        case .command: return "Command"
        case .text(let text): return text
        }
    }

    private var symbolName: String? {
        switch self {
        case .returnKey: return "return"
        case .escape: return "escape"
        case .upArrow: return "arrow.up"
        case .downArrow: return "arrow.down"
        case .leftArrow: return "arrow.left"
        case .rightArrow: return "arrow.right"
        case .command: return "command"
        case .text: return nil
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        if self == .command { return event.modifierFlags.contains(.command) }
        if case .text(let text) = self {
            return !text.isEmpty && event.charactersIgnoringModifiers?.lowercased() == text.lowercased()
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        return keyCodes.contains(event.keyCode)
    }

    private var keyCodes: [UInt16] {
        switch self {
        case .returnKey: return [36, 76]
        case .escape: return [53]
        case .upArrow: return [126]
        case .downArrow: return [125]
        case .leftArrow: return [123]
        case .rightArrow: return [124]
        case .command, .text: return []
        }
    }

    func image(label: String? = nil, font: NSFont = .systemFont(ofSize: 12)) -> NSImage {
        let symbol = symbolName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(Self.symbolConfiguration)
        }
        let keycap = Self.keycapImage(symbol: symbol, text: symbol == nil ? name : "")
        guard let label, !label.isEmpty else { return keycap }
        return Self.labeledImage(label, keycap: keycap, font: font)
    }

    private static func labeledImage(_ label: String, keycap: NSImage, font: NSFont) -> NSImage {
        let label = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
        let labelSize = label.size()
        let width = ceil(labelSize.width) + labelSpacing + keycap.size.width
        let height = max(ceil(labelSize.height), keycap.size.height)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
            label.draw(in: NSRect(x: 0, y: floor((bounds.height - labelSize.height) / 2),
                                   width: ceil(labelSize.width), height: labelSize.height))
            keycap.draw(in: NSRect(x: bounds.width - keycap.size.width,
                                   y: floor((bounds.height - keycap.size.height) / 2),
                                   width: keycap.size.width, height: keycap.size.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func keycapImage(symbol: NSImage?, text: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pointSize, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: text, attributes: attributes)
        let contentSize = symbol?.size ?? text.size()
        let width = symbol == nil ? max(keycapSize, ceil(contentSize.width) + 14) : keycapSize
        let image = NSImage(size: NSSize(width: width, height: keycapSize), flipped: false) { bounds in
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.375, dy: 0.375), xRadius: 6, yRadius: 6)
            outline.lineWidth = 0.75
            NSColor.black.withAlphaComponent(0.4).setStroke()
            outline.stroke()
            let contentRect = NSRect(x: floor((bounds.width - contentSize.width) / 2),
                                     y: floor((bounds.height - contentSize.height) / 2),
                                     width: contentSize.width, height: contentSize.height)
            if let symbol {
                symbol.draw(in: contentRect)
            } else {
                text.draw(in: contentRect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class KeyboardHintView: NSView {
    var hint: KeyboardHint {
        didSet { resetKeyPress(); updateContent() }
    }
    var label: String? {
        didSet { updateContent() }
    }
    private let labelFont: NSFont
    private let tracksKeyboardEvents: Bool
    private let imageView = NSImageView()
    private let pressBackground = CALayer()
    private var keycapSize = NSSize(width: KeyboardHint.keycapSize, height: KeyboardHint.keycapSize)
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var pressedKeyCode: UInt16?
    private var pendingKeyReleaseAction: (() -> Void)?
    private(set) var isKeyPressed = false
    var onKeyRelease: (() -> Void)?

    init(_ hint: KeyboardHint, label: String? = nil, font: NSFont = .systemFont(ofSize: 12),
         tracksKeyboardEvents: Bool = true) {
        self.hint = hint
        self.label = label
        labelFont = font
        self.tracksKeyboardEvents = tracksKeyboardEvents
        super.init(frame: .zero)
        wantsLayer = true
        pressBackground.name = "keyboardHintPressBackground"
        pressBackground.cornerRadius = 6
        pressBackground.opacity = 0
        layer?.addSublayer(pressBackground)
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityChildren([])
        updateContent()
    }

    required init?(coder: NSCoder) { fatalError("Use init(_:label:font:)") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pressBackground.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
            CATransaction.commit()
        }
    }

    override func layout() {
        super.layout()
        let frame = NSRect(x: imageView.frame.maxX - keycapSize.width, y: imageView.frame.midY - keycapSize.height / 2,
                           width: keycapSize.width, height: keycapSize.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pressBackground.frame = frame.insetBy(dx: 0.375, dy: 0.375)
        CATransaction.commit()
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingKeys()
        guard tracksKeyboardEvents, let window else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            if window.isKeyWindow && self.canShowKeyPress {
                self.handleKeyEvent(event)
            } else {
                self.resetKeyPress()
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: window, queue: .main) { [weak self] _ in
            self?.resetKeyPress()
        }
    }

    private var canShowKeyPress: Bool {
        guard !isHiddenOrHasHiddenAncestor else { return false }
        var ancestor: NSView? = self
        while let view = ancestor {
            if view.isAccessibilityHidden() { return false }
            if let control = view as? NSControl, !control.isEnabled { return false }
            ancestor = view.superview
        }
        return true
    }

    func handleKeyEvent(_ event: NSEvent) {
        if hint == .command {
            setKeyPressed(event.modifierFlags.contains(.command))
        } else if event.type == .keyDown && hint.matches(event) {
            pressedKeyCode = event.keyCode
            setKeyPressed(true)
        } else if event.type == .keyUp && event.keyCode == pressedKeyCode {
            let action = pendingKeyReleaseAction
            resetKeyPress()
            onKeyRelease?()
            action?()
        }
    }

    func performAfterKeyRelease(_ action: @escaping () -> Void) {
        if isKeyPressed {
            pendingKeyReleaseAction = action
        } else {
            action()
        }
    }

    func setKeyPressed(_ pressed: Bool) {
        guard isKeyPressed != pressed else { return }
        isKeyPressed = pressed
        let fromOpacity = pressBackground.presentation()?.opacity ?? pressBackground.opacity
        pressBackground.removeAnimation(forKey: "press")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pressBackground.opacity = pressed ? 1 : 0
        CATransaction.commit()
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = fromOpacity
        animation.toValue = pressBackground.opacity
        animation.duration = pressed ? 0.1 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pressBackground.add(animation, forKey: "press")
    }

    private func resetKeyPress() {
        pressedKeyCode = nil
        pendingKeyReleaseAction = nil
        setKeyPressed(false)
    }

    private func stopObservingKeys() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        eventMonitor = nil
        resignObserver = nil
        resetKeyPress()
    }

    override var intrinsicContentSize: NSSize {
        imageView.image?.size ?? NSSize(width: KeyboardHint.keycapSize, height: KeyboardHint.keycapSize)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updateContent() {
        imageView.image = hint.image(label: label, font: labelFont)
        keycapSize = hint.image().size
        let hasLabel = !(label ?? "").isEmpty
        imageView.contentTintColor = .labelColor
        let description = hasLabel ? "\(label!) (\(hint.name))" : hint.name
        setAccessibilityLabel(description)
        toolTip = description
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
}
