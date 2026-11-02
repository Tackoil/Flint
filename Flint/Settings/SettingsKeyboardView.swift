import AppKit

@MainActor
final class SettingsKeyboardView: NSView {
    var controls: () -> [NSView] = { [] }
    var navigationControls: (() -> [NSView])?
    var sidebarControl: () -> NSView? = { nil }
    weak var selectedControl: NSView?
    weak var lastContentControl: NSView?
    var actions: () -> [SettingsAction] = { [] }
    var primaryAction: (NSView?) -> SettingsAction? = { _ in nil }
    var isRecording: () -> Bool = { false }
    var cancelRecording: () -> Void = {}
    var onCancel: () -> Void = {}
    var onSectionArrow: ((NSView, Int) -> Bool)?
    var editorActions: [SettingsAction] = [] { didSet { rebuildFooter() } }
    private let footerContent = Appearance.stack([], spacing: 12)
    private(set) var footer: NSView!
    private let navigationHint = Appearance.stack([
        Appearance.label("Navigate", size: 12, color: .labelColor),
        KeyboardHintView(.upArrow, tracksKeyboardEvents: false), KeyboardHintView(.downArrow, tracksKeyboardEvents: false)
    ], spacing: 4)
    private let backButton = SettingsHintButton(title: "Back", hint: .escape)
    private let primaryButton = SettingsHintButton(title: "Activate", hint: .returnKey)
    private let menuButton = SettingsHintButton(title: "Actions", hint: .text("⌘K"))
    private let ring = SettingsFocusRing()
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    var usesKeyboard = false
    var trackingMenus = Set<ObjectIdentifier>()
    var actionsPopover: SettingsActionsPopover?
    private var isRefreshingActions = false

    init(footerLeadingInset: CGFloat = 24, footerBottomInset: CGFloat = 18) {
        super.init(frame: .zero)
        wantsLayer = true
        ring.wantsLayer = true
        ring.isHidden = true
        addSubview(ring)
        footer = Appearance.actionGroup(content: footerContent)
        footer.setAccessibilityLabel("Settings actions")
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: footerLeadingInset),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerBottomInset),
            footer.heightAnchor.constraint(equalToConstant: 36)
        ])
        backButton.onClick = { [weak self] in self?.navigateBack() }
        primaryButton.onClick = { [weak self] in self?.activateFocusedControl() }
        menuButton.onClick = { [weak self] in self?.showActions() }
        rebuildFooter()
    }

    required init?(coder: NSCoder) { fatalError("Use init(footerLeadingInset:)") }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() { super.layout(); updateFocusRing(); layoutActionsPopover() }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp]) {
            [weak self, weak window] event in
            guard let self, let window, event.window === window, window.attachedSheet == nil else { return event }
            return self.observe(event)
        }
        for name in [NSTableView.selectionDidChangeNotification, NSControl.textDidChangeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in MainActor.assumeIsolated { self?.handleNotification(notification) }
            })
        }
        refreshActions()
    }

    private func handleNotification(_ notification: Notification) {
        if handleMenuTracking(notification) { return }
        if let source = notification.object as? NSView {
            guard source.isDescendant(of: self) else { return }
        } else {
            guard let source = notification.object as? NSWindow, source === window else { return }
        }
        if [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification].contains(notification.name) {
            resetKeyFeedback()
            dismissActions(animated: false)
        }
        refreshActions()
    }

    private func stopObserving() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        trackingMenus.removeAll()
    }

    private func observe(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            if !isRecording() && trackingMenus.isEmpty { showKeyFeedback(event) }
            return handleKeyDown(event) ? nil : event
        }
        if event.type == .keyUp { resetKeyFeedback(); actionsPopover?.resetKeyFeedback() }
        if event.type == .leftMouseDown {
            if dismissActionsOutside(event) { return nil }
            usesKeyboard = false
        }
        DispatchQueue.main.async { [weak self] in self?.refreshActions() }
        return event
    }

    private func showKeyFeedback(_ event: NSEvent) {
        if editorActions.isEmpty {
            navigationHint.arrangedSubviews.compactMap { $0 as? KeyboardHintView }.forEach {
                $0.setKeyPressed($0.hint.matches(event))
            }
            backButton.hintView.setKeyPressed(KeyboardHint.escape.matches(event))
            primaryButton.hintView.setKeyPressed(KeyboardHint.returnKey.matches(event))
            menuButton.hintView.setKeyPressed(event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "k")
        } else {
            primaryButton.hintView.setKeyPressed(KeyboardHint.returnKey.matches(event))
            for (action, view) in zip(editorActions, footerContent.arrangedSubviews.dropFirst()) {
                (view as? SettingsHintButton)?.hintView.setKeyPressed(action.matches(event))
            }
        }
    }

    private func resetKeyFeedback() {
        footerContent.arrangedSubviews.compactMap { $0 as? SettingsHintButton }.forEach { $0.hintView.setKeyPressed(false) }
        navigationHint.arrangedSubviews.compactMap { $0 as? KeyboardHintView }.forEach { $0.setKeyPressed(false) }
    }

    var focusedControl: NSView? {
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor {
            return editor.delegate as? NSView
        }
        let responder = window?.firstResponder as? NSView
        return responder === self ? selectedControl : responder
    }

    var availableControls: [NSView] {
        controls().filter { !$0.isHiddenOrHasHiddenAncestor && ($0 as? NSControl)?.isEnabled != false }
    }

    func activateFocusedControl() {
        guard let action = currentPrimaryAction(), action.isEnabled else { return }
        action.perform()
        refreshActions()
    }

    func refreshActions() {
        guard !isRefreshingActions else { return }
        isRefreshingActions = true
        defer { isRefreshingActions = false }
        restoreAvailableFocus()
        let primary = currentPrimaryAction()
        primaryButton.update(title: primary?.title ?? "Activate", enabled: primary?.isEnabled == true)
        navigationHint.isHidden = isEditingText
        backButton.update(title: isEditingText ? "Done" : isInSidebar ? "Close" : "Back", enabled: true)
        updateEditorBackAction()
        updateFocusRing()
        footer.needsLayout = true
    }

    private func updateEditorBackAction() {
        guard let index = editorActions.firstIndex(where: { $0.key == "\u{1b}" }),
              let button = footerContent.arrangedSubviews[index + 1] as? SettingsHintButton else { return }
        button.update(title: isEditingText ? "Back" : "Cancel", enabled: true)
        button.onClick = { [weak self] in self?.navigateBack() }
    }

    private func restoreAvailableFocus() {
        guard let window, window.attachedSheet == nil, !isRecording(), let first = availableControls.first else { return }
        if !availableControls.contains(where: { $0 === focusedControl }) { focus(first, editing: false) }
    }

    private func updateFocusRing() {
        guard usesKeyboard, !isInSidebar, let control = focusedControl, control !== self, control.isDescendant(of: self),
              !control.isHiddenOrHasHiddenAncestor, !isEditingText else {
            ring.isHidden = true
            return
        }
        ring.frame = bounds
        ring.control = control
        ring.needsDisplay = true
        ring.isHidden = false
        if actionsPopover == nil && subviews.last !== ring { addSubview(ring, positioned: .above, relativeTo: nil) }
    }

    private func rebuildFooter() {
        footerContent.arrangedSubviews.forEach { footerContent.removeArrangedSubview($0); $0.removeFromSuperview() }
        if editorActions.isEmpty {
            [navigationHint, backButton, primaryButton, menuButton].forEach { footerContent.addArrangedSubview($0) }
        } else {
            footerContent.addArrangedSubview(primaryButton)
            for action in editorActions {
                let hint: KeyboardHint = action.key == "\u{1b}" ? .escape : .text("⌘↵")
                let button = SettingsHintButton(title: action.title, hint: hint)
                button.onClick = action.perform
                button.update(title: action.title, enabled: action.isEnabled)
                footerContent.addArrangedSubview(button)
            }
        }
        footer.needsLayout = true
    }

}
