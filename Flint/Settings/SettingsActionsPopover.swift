import AppKit

private final class SettingsActionsDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class SettingsPopoverActionRow: NSButton {
    var onHover: (() -> Void)?
    var onChoose: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    private var hoverArea: NSTrackingArea?
    private var shortcutView: KeyboardHintView?

    init(action: SettingsAction) {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        focusRingType = .none
        isEnabled = action.isEnabled
        alphaValue = action.isEnabled ? 1 : 0.4
        wantsLayer = true
        layer?.cornerRadius = 6
        target = self
        self.action = #selector(choose)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(action.title)
        let label = Appearance.label(action.title, size: 13, color: .labelColor)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let shortcut = action.key.isEmpty ? nil : KeyboardHintView(Self.hint(action), tracksKeyboardEvents: false)
        shortcutView = shortcut
        let content = Appearance.stack([label, Appearance.spacer()] + (shortcut.map { [$0] } ?? []), spacing: 8)
        setAccessibilityHelp(Self.shortcut(action))
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setAccessibilityHidden(true)
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(action:)") }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isSelected ? NSColor.labelColor.withAlphaComponent(0.1) : .clear).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { onHover?() } }
    @objc private func choose() { if isEnabled { onChoose?() } }

    func setKeyPressed(_ pressed: Bool) { shortcutView?.setKeyPressed(pressed) }

    static func idealWidth(for action: SettingsAction) -> CGFloat {
        let titleWidth = (action.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        let shortcutWidth = action.key.isEmpty ? 0 : hint(action).image().size.width
        return ceil(titleWidth + shortcutWidth + 36)
    }

    private static func hint(_ action: SettingsAction) -> KeyboardHint {
        if action.modifiers.isEmpty && action.key == "\u{1b}" { return .escape }
        if action.modifiers.isEmpty && action.key == "\r" { return .returnKey }
        return .text(shortcut(action))
    }

    private static func shortcut(_ action: SettingsAction) -> String {
        guard !action.key.isEmpty else { return "" }
        let flags: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifiers = flags.filter { action.modifiers.contains($0.0) }.map(\.1).joined()
        let keys = ["\r": "↵", "\u{1b}": "⎋", "\u{7f}": "⌫"]
        return modifiers + (keys[action.key] ?? action.key.uppercased())
    }
}

@MainActor
final class SettingsActionsPopover: NSView {
    let actions: [SettingsAction]
    private(set) var selectedIndex: Int?
    var onChoose: ((SettingsAction) -> Void)?
    var onDismiss: (() -> Void)?
    private let scroll: NSScrollView
    private let document = SettingsActionsDocument()
    private var rows: [SettingsPopoverActionRow] = []
    private let surface: NSView
    var transition: SettingsPopoverTransition?
    var transitionProgress: CGFloat = 1
    var targetFrame: NSRect = .zero
    private(set) var isDismissing = false
    let idealWidth: CGFloat
    private static let rowHeight: CGFloat = 32
    var idealHeight: CGFloat { CGFloat(actions.count) * Self.rowHeight + 16 }

    init(actions: [SettingsAction]) {
        self.actions = actions
        idealWidth = max(260, (actions.map { SettingsPopoverActionRow.idealWidth(for: $0) }.max() ?? 0) + 16)
        let scrollView = NSScrollView()
        scroll = scrollView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = nil
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.cornerRadius = 12
            glass.contentView = scrollView
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 12
            effect.layer?.masksToBounds = true
            effect.addSubview(scrollView)
            surface = effect
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 16
        layer?.shadowOffset = NSSize(width: 0, height: -5)
        addSubview(surface)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Settings Actions")
        configureRows()
    }

    required init?(coder: NSCoder) { fatalError("Use init(actions:)") }
    deinit { transition?.stop() }
    override func hitTest(_ point: NSPoint) -> NSView? { isDismissing ? nil : super.hitTest(point) }

    func prepareForDismissal() {
        isDismissing = true
        onChoose = nil
        onDismiss = nil
        setAccessibilityHidden(true)
    }

    func resetKeyFeedback() { rows.forEach { $0.setKeyPressed(false) } }

    private func configureRows() {
        for (index, action) in actions.enumerated() {
            let row = SettingsPopoverActionRow(action: action)
            row.onHover = { [weak self] in self?.select(index) }
            row.onChoose = { [weak self] in self?.choose(index) }
            document.addSubview(row)
            rows.append(row)
        }
        if let first = actions.firstIndex(where: \.isEnabled) { select(first) }
    }

    override func layout() {
        super.layout()
        surface.frame = bounds
        scroll.frame = bounds
        document.setFrameSize(NSSize(width: bounds.width, height: idealHeight))
        scroll.tile()
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: idealHeight))
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 8, y: 8 + CGFloat(index) * Self.rowHeight,
                               width: max(0, document.bounds.width - 16), height: Self.rowHeight)
        }
        if let selectedIndex { document.scrollToVisible(rows[selectedIndex].frame) }
    }

    func select(_ index: Int) {
        guard actions.indices.contains(index), actions[index].isEnabled else { return }
        selectedIndex = index
        for (rowIndex, row) in rows.enumerated() {
            row.isSelected = rowIndex == index
            row.setAccessibilityValue(row.isSelected ? "Selected" : "")
        }
        document.scrollToVisible(rows[index].frame)
    }

    private func moveSelection(by offset: Int) {
        let enabled = actions.indices.filter { actions[$0].isEnabled }
        guard !enabled.isEmpty else { return }
        let index = selectedIndex.flatMap { enabled.firstIndex(of: $0) } ?? 0
        select(enabled[min(max(index + offset, 0), enabled.count - 1)])
    }

    private func choose(_ index: Int) {
        guard !isDismissing, actions.indices.contains(index), actions[index].isEnabled else { return }
        select(index)
        rows[index].setKeyPressed(true)
        onChoose?(actions[index])
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 || (modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "k") {
            if !event.isARepeat { onDismiss?() }
            return true
        }
        if handleNavigation(event, modifiers: modifiers) { return true }
        if !event.isARepeat, let index = actions.firstIndex(where: { $0.matches(event) && $0.isEnabled }) { choose(index) }
        return true
    }

    private func handleNavigation(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection([.command, .option, .control]).isEmpty else { return false }
        if [125, 126, 48].contains(event.keyCode) {
            let backwards = event.keyCode == 126 || (event.keyCode == 48 && modifiers.contains(.shift))
            moveSelection(by: backwards ? -1 : 1)
            return true
        }
        guard [36, 76, 49].contains(event.keyCode) else { return false }
        if !event.isARepeat, let selectedIndex { choose(selectedIndex) }
        return true
    }
}
