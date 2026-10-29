import AppKit

private final class LauncherDialogButton: NSButton {
    private let content: KeyboardHintView

    init(title: String, hint: KeyboardHint) {
        content = KeyboardHintView(hint, label: title, font: .systemFont(ofSize: 13), tracksKeyboardEvents: false)
        super.init(frame: .zero)
        self.title = ""
        setButtonType(.momentaryPushIn)
        isBordered = true
        bezelStyle = .push
        controlSize = .large
        if #available(macOS 26.0, *) {
            controlSize = .extraLarge
        } else {
            bezelStyle = .flexiblePush
        }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        // Keep native image-button sizing while the shared hint draws its animated background separately.
        image = NSImage(size: content.intrinsicContentSize)
        imagePosition = .imageOnly
        content.setAccessibilityHidden(true)
        addSubview(content)
        setAccessibilityLabel(title)
        setAccessibilityHelp("Press \(hint.name) to \(title.lowercased()).")
        toolTip = "\(title) (\(hint.name))"
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:hint:)") }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        content.frame = cell?.imageRect(forBounds: bounds) ?? bounds
    }

    func setKeyPressed(_ pressed: Bool) {
        content.setKeyPressed(pressed)
    }
}

final class LauncherDialogView: NSView {
    private let dialog = NSView()
    private let primaryButtonIndex: Int
    private var onResponse: ((Int) -> Void)?
    private var buttons: [LauncherDialogButton] = []
    private var pendingKey: (code: UInt16, index: Int)?
    private var resignObserver: NSObjectProtocol?

    init(title: String, message: String, buttonTitles: [String], onResponse: @escaping (Int) -> Void) {
        precondition(!buttonTitles.isEmpty)
        primaryButtonIndex = buttonTitles.count - 1
        self.onResponse = onResponse
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilitySubrole(.dialog)
        setAccessibilityLabel(title)
        setAccessibilityModal(true)
        configureDialog(title: title, message: message, buttonTitles: buttonTitles)
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:message:buttonTitles:onResponse:)") }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        resetKeyPress()
        guard let window else { return }
        window.makeFirstResponder(self)
        window.defaultButtonCell = nil
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: window, queue: .main) { [weak self] _ in
            self?.resetKeyPress()
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    override func layout() {
        super.layout()
        dialog.layer?.shadowPath = CGPath(roundedRect: dialog.bounds, cornerWidth: 22, cornerHeight: 22, transform: nil)
    }

    private func configureDialog(title: String, message: String, buttonTitles: [String]) {
        let titleLabel = Appearance.label(title, size: 15, weight: .semibold, color: .labelColor)
        let messageLabel = Appearance.label(message, size: 13, color: .labelColor)
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.preferredMaxLayoutWidth = 312
        buttons = buttonTitles.enumerated().map { index, title in
            let isPrimary = index == primaryButtonIndex
            let button = LauncherDialogButton(title: title, hint: isPrimary ? .returnKey : .escape)
            button.target = self
            button.action = #selector(clickedButton(_:))
            button.tag = index
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return button
        }
        let buttonRow = Appearance.stack(buttons, spacing: 12)
        buttonRow.distribution = .fillEqually
        let content = NSStackView(views: [titleLabel, messageLabel, buttonRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.setCustomSpacing(24, after: messageLabel)
        let material = dialogMaterial(content: content)
        dialog.wantsLayer = true
        dialog.layer?.shadowColor = NSColor.black.cgColor
        dialog.layer?.shadowOpacity = 0.22
        dialog.layer?.shadowRadius = 24
        dialog.layer?.shadowOffset = CGSize(width: 0, height: -8)
        dialog.addSubview(material)
        addSubview(dialog)
        for view in [dialog, material, content] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            dialog.widthAnchor.constraint(equalToConstant: 360),
            dialog.centerXAnchor.constraint(equalTo: centerXAnchor),
            dialog.centerYAnchor.constraint(equalTo: centerYAnchor),
            material.leadingAnchor.constraint(equalTo: dialog.leadingAnchor),
            material.trailingAnchor.constraint(equalTo: dialog.trailingAnchor),
            material.topAnchor.constraint(equalTo: dialog.topAnchor),
            material.bottomAnchor.constraint(equalTo: dialog.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: material.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -24),
            messageLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
    }

    private func dialogMaterial(content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = nil
            glass.cornerRadius = 22
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 22
        material.layer?.masksToBounds = true
        material.addSubview(content)
        return material
    }

    @objc private func clickedButton(_ sender: NSButton) { respond(at: sender.tag) }

    private func respond(at index: Int) {
        resetKeyPress()
        let response = onResponse
        onResponse = nil
        window?.defaultButtonCell = nil
        removeFromSuperview()
        response?(index)
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat, pendingKey == nil,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return }
        let responses: [UInt16: Int] = [36: primaryButtonIndex, 76: primaryButtonIndex, 53: 0]
        guard let index = responses[event.keyCode] else { return }
        pendingKey = (event.keyCode, index)
        buttons[index].setKeyPressed(true)
    }

    override func keyUp(with event: NSEvent) {
        guard let pendingKey, pendingKey.code == event.keyCode else { return }
        respond(at: pendingKey.index)
    }

    private func resetKeyPress() {
        pendingKey = nil
        buttons.forEach { $0.setKeyPressed(false) }
    }

    override func insertNewline(_ sender: Any?) { respond(at: primaryButtonIndex) }
    override func cancelOperation(_ sender: Any?) { respond(at: 0) }
}
