import AppKit

private final class LauncherSearchIcon: NSView {
    private let search = Appearance.symbol("magnifyingglass", size: 16, color: .secondaryLabelColor)
    private let calculator = Appearance.symbol("plus.forwardslash.minus", size: 16, color: .secondaryLabelColor)
    private var isCalculator = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for icon in [search, calculator] {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.wantsLayer = true
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor),
                icon.trailingAnchor.constraint(equalTo: trailingAnchor),
                icon.topAnchor.constraint(equalTo: topAnchor),
                icon.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        search.setAccessibilityLabel("Search")
        calculator.setAccessibilityLabel("Calculator")
        calculator.alphaValue = 0
        calculator.setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func setCalculatorMode(_ enabled: Bool) {
        guard isCalculator != enabled else { return }
        isCalculator = enabled
        search.setAccessibilityHidden(enabled)
        calculator.setAccessibilityHidden(!enabled)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Appearance.launcherTransitionDuration(for: window)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            search.animator().alphaValue = enabled ? 0 : 1
            calculator.animator().alphaValue = enabled ? 1 : 0
        }
    }
}

private final class LauncherFooterView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        var ancestor = hit
        while let view = ancestor, view !== self {
            if view is NSControl { return hit }
            ancestor = view.superview
        }
        return nil
    }
}

private final class LauncherOpenButton: NSButton {
    private let content = KeyboardHintView(.returnKey, label: "Open Application")
    var isReturnKeyPressed: Bool { content.isKeyPressed }

    func updateTitle(_ title: String) {
        content.label = title
        setAccessibilityLabel(title)
        toolTip = "\(title) (\(KeyboardHint.returnKey.name))"
    }

    override var isEnabled: Bool {
        didSet { subviews.first?.alphaValue = isEnabled ? 1 : 0.4 }
    }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        (cell as? NSButtonCell)?.highlightsBy = []
        setAccessibilityLabel("Open Application")
        toolTip = "Open selected application (\(KeyboardHint.returnKey.name))"
        content.onKeyRelease = { [weak self] in self?.performClick(nil) }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

}

private final class LauncherRoundingModeButton: NSButton {
    private let content = KeyboardHintView(.upArrow, label: "Edit expression")

    override var acceptsFirstResponder: Bool { false }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        (cell as? NSButtonCell)?.highlightsBy = []
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(isRounding: true)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func update(isRounding: Bool) {
        let hint: KeyboardHint = isRounding ? .upArrow : .downArrow
        let label = isRounding ? "Edit expression" : "Round result"
        if content.hint != hint { content.hint = hint }
        if content.label != label { content.label = label }
        setAccessibilityLabel(label)
        toolTip = "\(label) (\(hint.name))"
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}

final class LauncherHeaderFooter {
    static let searchBarHeight: CGFloat = LauncherLayout.cornerRadius * 2
    let searchField = NSTextField()
    let openButton: NSButton = LauncherOpenButton()
    let settingsButton = Appearance.button("")
    let roundingModeButton: NSButton = LauncherRoundingModeButton()
    private let searchIcon = LauncherSearchIcon()
    private let navigation = Appearance.stack([
        Appearance.label("Navigate", size: 12, color: .labelColor), KeyboardHintView(.upArrow), KeyboardHintView(.downArrow)
    ], spacing: 4)
    private let precisionLabel = Appearance.label("", size: 12, color: .labelColor)
    private let precisionKeys = Appearance.stack([KeyboardHintView(.leftArrow), KeyboardHintView(.rightArrow)], spacing: 4)
    private lazy var precisionControls = Appearance.stack([precisionLabel, precisionKeys], spacing: 4)
    private let timestampUnitHint = KeyboardHintView(.rightArrow, label: "ms")
    private var footerContent: NSView?
    private var actionGroup: ActionGroupView?

    func searchBar() -> NSView {
        NSLayoutConstraint.activate([
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20)
        ])
        let searchFont = NSFont.systemFont(ofSize: 18)
        searchField.font = searchFont
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search applications, actions, or calculate…",
            attributes: [.font: searchFont, .foregroundColor: NSColor.secondaryLabelColor]
        )
        searchField.textColor = .labelColor
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.setAccessibilityLabel("Search applications, actions, or calculate")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return searchBarLayout(icon: searchIcon)
    }

    private func searchBarLayout(icon: NSView) -> NSView {
        let bar = NSView()
        for item in [icon, searchField] {
            item.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(item)
        }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: Self.searchBarHeight),
            icon.centerXAnchor.constraint(equalTo: bar.leadingAnchor, constant: LauncherLayout.iconCenterX),
            icon.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: LauncherLayout.textLeading),
            searchField.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -LauncherLayout.contentInset),
            searchField.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 0.5)
        ])
        return bar
    }

    func footer() -> NSView {
        navigation.setAccessibilityLabel("Use the Up and Down arrow keys to navigate")
        precisionControls.isHidden = true
        roundingModeButton.isHidden = true
        timestampUnitHint.isHidden = true
        let actions = Appearance.actionGroup(content: Appearance.stack(
            [openButton, navigation, precisionControls, roundingModeButton, timestampUnitHint], spacing: 16))
        actions.wantsLayer = true
        actionGroup = actions as? ActionGroupView
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        settingsButton.imagePosition = .imageOnly
        settingsButton.isBordered = true
        settingsButton.bezelStyle = .circular
        if #available(macOS 26.0, *) {
            settingsButton.bezelStyle = .glass
            settingsButton.borderShape = .circle
        }
        settingsButton.toolTip = "Settings (⌘,)"
        settingsButton.setAccessibilityLabel("Settings")
        NSLayoutConstraint.activate([
            settingsButton.widthAnchor.constraint(equalToConstant: LauncherLayout.floatingControlSize),
            settingsButton.heightAnchor.constraint(equalToConstant: LauncherLayout.floatingControlSize)
        ])
        let content = Appearance.stack([settingsButton, actions], spacing: 13)
        footerContent = content
        return inset(content,
                     horizontal: LauncherLayout.floatingControlInset, height: LauncherLayout.footerHeight)
    }

    func updateActionTitle(_ title: String) {
        animateActionLayout {
            (openButton as? LauncherOpenButton)?.updateTitle(title)
        }
    }

    func setCalculatorMode(_ isCalculator: Bool) {
        animateActionLayout {
            navigation.isHidden = isCalculator
        }
        searchIcon.setCalculatorMode(isCalculator)
    }

    func updatePrecision(_ decimalPlaces: Int?, isRounding: Bool) {
        animateActionLayout {
            configurePrecision(decimalPlaces, isRounding: isRounding)
        }
    }

    private func configurePrecision(_ decimalPlaces: Int?, isRounding: Bool) {
        precisionControls.isHidden = decimalPlaces == nil || !isRounding
        precisionKeys.isHidden = !isRounding
        roundingModeButton.isHidden = decimalPlaces == nil
        (roundingModeButton as? LauncherRoundingModeButton)?.update(isRounding: isRounding)
        precisionLabel.stringValue = decimalPlaces.map { places in
            let count = abs(places)
            let digits = count == 1 ? "digit" : "digits"
            let side = places < 0 ? "before" : "after"
            return "\(count) \(digits) \(side) decimal"
        } ?? ""
        let help = isRounding
            ? "Left decreases decimal places; Right increases them. Up edits the expression."
            : "Left and Right move the cursor. Down rounds the result."
        precisionControls.setAccessibilityLabel("\(precisionLabel.stringValue) point. \(help)")
        precisionControls.toolTip = help
    }

    var isReturnKeyPressed: Bool { (openButton as? LauncherOpenButton)?.isReturnKeyPressed == true }

    func setTimestampUnitSwitching(_ unit: TimestampCalculation.Unit?) {
        animateActionLayout {
            configureTimestampUnitSwitching(unit)
        }
    }

    private func configureTimestampUnitSwitching(_ unit: TimestampCalculation.Unit?) {
        timestampUnitHint.isHidden = unit == nil
        guard let unit else { return }
        let hint: KeyboardHint = unit == .seconds ? .rightArrow : .leftArrow
        let label = unit == .seconds ? "ms" : "s"
        if timestampUnitHint.hint != hint { timestampUnitHint.hint = hint }
        if timestampUnitHint.label != label { timestampUnitHint.label = label }
        let destination = unit == .seconds ? "milliseconds" : "seconds"
        let help = "Switch to \(destination) (\(hint.name)). Modified arrow keys edit the input."
        timestampUnitHint.setAccessibilityLabel(help)
        timestampUnitHint.toolTip = help
    }

    private func animateActionLayout(_ updates: () -> Void) {
        let layoutRoot = footerContent?.window?.contentView ?? footerContent?.superview
        updates()
        actionGroup?.needsLayout = true
        layoutRoot?.layoutSubtreeIfNeeded()
    }

    private func inset(_ content: NSView, horizontal: CGFloat, height: CGFloat) -> NSView {
        let container = LauncherFooterView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: height),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontal),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontal),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
