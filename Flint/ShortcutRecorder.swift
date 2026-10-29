import AppKit

@MainActor
final class ShortcutRecorder: NSButton {
    var shortcut: LauncherShortcut = .commandSpace {
        didSet { if !isRecording { updateShortcutDisplay() } }
    }
    var onShortcutChange: ((LauncherShortcut) -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?
    var onValidationError: ((String?) -> Void)?
    private(set) var isRecording = false
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private let keycaps = Appearance.stack([], spacing: 5)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        bezelStyle = .rounded
        isBordered = false
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(toggleRecording)
        toolTip = "Click to record a shortcut. Escape cancels."
        setAccessibilityLabel("Launcher shortcut")
        setAccessibilityHelp("Activate, then press a shortcut. Escape cancels recording.")
        keycaps.translatesAutoresizingMaskIntoConstraints = false
        keycaps.setAccessibilityHidden(true)
        addSubview(keycaps)
        NSLayoutConstraint.activate([
            keycaps.centerXAnchor.constraint(equalTo: centerXAnchor),
            keycaps.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualTo: keycaps.widthAnchor, constant: 12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        updateShortcutDisplay()
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    private func updateShortcutDisplay() {
        title = ""
        keycaps.isHidden = false
        keycaps.arrangedSubviews.forEach {
            keycaps.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let modifiers = shortcut.modifiers.symbols
        var hints = modifiers.map { $0 == "⌘" ? KeyboardHint.command : .text(String($0)) }
        hints.append(.text(String(shortcut.title.dropFirst(modifiers.count))))
        hints.forEach { keycaps.addArrangedSubview(KeyboardHintView($0, tracksKeyboardEvents: false)) }
        setAccessibilityValue(shortcut.title)
    }

    @objc private func toggleRecording() {
        if isRecording { cancelRecording() } else { beginRecording() }
    }

    private func beginRecording() {
        guard let window else { return }
        isRecording = true
        keycaps.isHidden = true
        title = "Press shortcut…"
        setAccessibilityValue(title)
        contentTintColor = Appearance.accent
        window.makeFirstResponder(self)
        onValidationError?(nil)
        onRecordingStateChange?(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.consume(event)
        }
        let notifications = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification]
        windowObservers = notifications.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelRecording() }
            }
        }
    }

    private func consume(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        if event.type == .flagsChanged {
            title = modifiers.symbols + "…"
            setAccessibilityValue(title)
            return event
        }
        if event.keyCode == 53 {
            cancelRecording()
            return nil
        }
        if event.keyCode == 48 && modifiers.intersection([.command, .option, .control]).isEmpty {
            cancelRecording()
            return event
        }
        guard !event.isARepeat else { return nil }
        record(event, modifiers: modifiers)
        return nil
    }

    private func record(_ event: NSEvent, modifiers: ShortcutModifiers) {
        let shortcut = LauncherShortcut(
            keyCode: event.keyCode, modifiers: modifiers,
            characters: event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        )
        guard shortcut.isValid else {
            onValidationError?("Include Command, Option, or Control, or use a function key. Escape cancels.")
            return
        }
        cancelRecording()
        onShortcutChange?(shortcut)
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        updateShortcutDisplay()
        contentTintColor = nil
        onValidationError?(nil)
        onRecordingStateChange?(false)
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

private extension ShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, Self)] = [
            (.command, .command), (.option, .option), (.control, .control), (.shift, .shift)
        ]
        self = pairs.reduce([]) { eventFlags.contains($1.0) ? $0.union($1.1) : $0 }
    }
}
