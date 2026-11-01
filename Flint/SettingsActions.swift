import AppKit

struct SettingsAction {
    let title: String
    var key: String = ""
    var modifiers: NSEvent.ModifierFlags = .command
    var isEnabled = true
    var showsInMenu = true
    let perform: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
         isEnabled: Bool = true, showsInMenu: Bool = true, perform: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.showsInMenu = showsInMenu
        self.perform = perform
    }

    func matches(_ event: NSEvent) -> Bool {
        !key.isEmpty && event.charactersIgnoringModifiers?.lowercased() == key.lowercased()
            && event.modifierFlags.intersection([.command, .option, .control, .shift]) == modifiers
    }

    @MainActor init(button: NSButton, title: String, key: String = "",
                    modifiers: NSEvent.ModifierFlags = .command) {
        self.init(title, key: key, modifiers: modifiers,
                  isEnabled: button.isEnabled && !button.isHiddenOrHasHiddenAncestor) { [weak button] in
            button?.performClick(nil)
        }
    }
}

@MainActor
protocol SettingsKeyboardSection: AnyObject {
    var keyboardControls: [NSView] { get }
    var keyboardNavigationControls: [NSView] { get }
    var keyboardActions: [SettingsAction] { get }
    func keyboardPrimaryAction(for control: NSView?) -> SettingsAction?
}

final class SettingsButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        cell?.focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var acceptsFirstResponder: Bool { true }
}

final class SettingsSwitch: NSSwitch {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var acceptsFirstResponder: Bool { true }
}

final class SettingsFocusRing: NSView {
    weak var control: NSView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let control else { return }
        if let table = control as? NSTableView, table.selectedRow >= 0 { return }
        let selectedRow = row(containing: control)
        let rect = convert(selectedRow.bounds, from: selectedRow).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.075).setFill()
        path.fill()
        path.lineWidth = 0.5
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    private func row(containing control: NSView) -> NSView {
        var candidate: NSView? = control
        while let view = candidate {
            if view.identifier?.rawValue == "settingsRow" { return view }
            candidate = view.superview
        }
        return control
    }
}

final class SettingsHintButton: NSButton {
    let hintView: KeyboardHintView
    var onClick: (() -> Void)?

    init(title: String, hint: KeyboardHint) {
        hintView = KeyboardHintView(hint, label: title, tracksKeyboardEvents: false)
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        (cell as? NSButtonCell)?.highlightsBy = []
        setAccessibilityLabel(title)
        hintView.setAccessibilityHidden(true)
        hintView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintView)
        target = self
        action = #selector(clicked)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            hintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hintView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:hint:)") }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    @objc private func clicked() { onClick?() }

    func update(title: String, enabled: Bool) {
        hintView.label = title
        hintView.alphaValue = enabled ? 1 : 0.4
        isEnabled = enabled
        setAccessibilityLabel(title)
    }
}
