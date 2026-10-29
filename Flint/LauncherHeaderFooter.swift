import AppKit
import CoreText

private final class LauncherSearchField: NSTextField, NSLayoutManagerDelegate {
    override var stringValue: String { didSet { configureEditor() } }
    private lazy var returnGlyph: CGGlyph = {
        let font = self.font ?? .systemFont(ofSize: 18)
        var character: UniChar = 0x23CE
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
        return glyph
    }()

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        configureEditor()
        return accepted
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        configureEditor()
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        configureEditor()
    }

    private func configureEditor() {
        guard let editor = currentEditor() as? NSTextView, let container = editor.textContainer else { return }
        editor.isHorizontallyResizable = false
        editor.layoutManager?.delegate = self
        container.widthTracksTextView = false
        container.maximumNumberOfLines = 1
        container.lineBreakMode = .byTruncatingTail
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes[.paragraphStyle] = paragraph
        // Truncate the presentation without removing characters or paragraph breaks.
        editor.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                         range: NSRange(location: 0, length: editor.string.utf16.count))
        container.containerSize = NSSize(width: max(1, editor.bounds.width), height: .greatestFiniteMagnitude)
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let source = layoutManager.textStorage?.string as NSString? else { return 0 }
        let breaks = (0..<range.length).filter {
            characterIndexes[$0] < source.length && [10, 13, 0x85, 0x2028, 0x2029].contains(Int(source.character(at: characterIndexes[$0])))
        }
        guard !breaks.isEmpty else { return 0 }
        layoutManager.setGlyphs(glyphs, properties: props, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        for index in breaks {
            var characterIndex = characterIndexes[index]
            let isCRLFContinuation = source.character(at: characterIndex) == 10
                && characterIndex > 0 && source.character(at: characterIndex - 1) == 13
            var glyph = isCRLFContinuation ? 0 : returnGlyph
            var property: NSLayoutManager.GlyphProperty = isCRLFContinuation ? .null : []
            // Substitute only the drawn glyph; the source still contains its original line break.
            layoutManager.setGlyphs(&glyph, properties: &property, characterIndexes: &characterIndex,
                                   font: self.font ?? font, forGlyphRange: NSRange(location: range.location + index, length: 1))
        }
        return range.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        action.intersection([.lineBreak, .paragraphBreak]).isEmpty ? action : []
    }
}

private final class LauncherSearchIcon: NSView {
    private let search = Appearance.symbol("magnifyingglass", size: 16, color: .secondaryLabelColor)
    private let calculator = Appearance.symbol("plus.forwardslash.minus", size: 16, color: .secondaryLabelColor)
    private let color = Appearance.symbol("paintpalette", size: 16, color: .secondaryLabelColor)
    private let translation = Appearance.symbol("character.bubble", size: 16, color: .secondaryLabelColor)
    private var mode = "search"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for icon in [search, calculator, color, translation] {
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
        color.setAccessibilityLabel("Color conversion")
        color.alphaValue = 0
        color.setAccessibilityHidden(true)
        translation.setAccessibilityLabel("Translation")
        translation.alphaValue = 0
        translation.setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func setCalculatorMode(_ enabled: Bool, isColor: Bool, isTranslation: Bool) {
        let next = isTranslation ? "translation" : (isColor ? "color" : (enabled ? "calculator" : "search"))
        guard mode != next else { return }
        mode = next
        let icons = [(search, "search"), (calculator, "calculator"), (color, "color"), (translation, "translation")]
        icons.forEach { $0.0.setAccessibilityHidden($0.1 != next) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Appearance.launcherTransitionDuration(for: window)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            icons.forEach { $0.0.animator().alphaValue = $0.1 == next ? 1 : 0 }
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
    var isReturnKeyPressed: Bool { content.hint == .returnKey && content.isKeyPressed }

    func updateTitle(_ title: String, hint: KeyboardHint) {
        if content.hint != hint { content.hint = hint }
        content.label = title
        setAccessibilityLabel(title)
        toolTip = "\(title) (\(hint.name))"
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

private final class LauncherModeButton: NSButton {
    let content = KeyboardHintView(.upArrow, label: "Edit expression")

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
        update(hint: isRounding ? .upArrow : .downArrow,
               label: isRounding ? "Edit expression" : "Round result")
    }

    func update(isSwitchingColors: Bool) {
        update(hint: isSwitchingColors ? .upArrow : .downArrow,
               label: isSwitchingColors ? "Edit color" : "Switch format")
    }

    func update(isSwitchingNumberBases: Bool) {
        update(hint: isSwitchingNumberBases ? .upArrow : .downArrow,
               label: isSwitchingNumberBases ? "Edit number" : "Switch base")
    }

    private func update(hint: KeyboardHint, label: String) {
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
    let searchField: NSTextField = LauncherSearchField()
    let openButton: NSButton = LauncherOpenButton()
    let settingsButton = Appearance.button("")
    let roundingModeButton: NSButton = LauncherModeButton()
    let colorModeButton: NSButton = LauncherModeButton()
    let numberBaseModeButton: NSButton = LauncherModeButton()
    let translationExitButton: NSButton = LauncherOpenButton()
    private let searchIcon = LauncherSearchIcon()
    private let navigation = Appearance.stack([
        Appearance.label("Navigate", size: 12, color: .labelColor), KeyboardHintView(.upArrow), KeyboardHintView(.downArrow)
    ], spacing: 4)
    private let precisionLabel = Appearance.label("", size: 12, color: .labelColor)
    private let precisionKeys = Appearance.stack([KeyboardHintView(.leftArrow), KeyboardHintView(.rightArrow)], spacing: 4)
    private lazy var precisionControls = Appearance.stack([precisionLabel, precisionKeys], spacing: 4)
    private let previousColorFormat = KeyboardHintView(.leftArrow)
    private let nextColorFormat = KeyboardHintView(.rightArrow)
    private lazy var colorFormatControls = Appearance.stack([previousColorFormat, nextColorFormat], spacing: 12)
    private let previousNumberBase = KeyboardHintView(.leftArrow)
    private let nextNumberBase = KeyboardHintView(.rightArrow)
    private lazy var numberBaseControls = Appearance.stack([previousNumberBase, nextNumberBase], spacing: 12)
    private let timestampUnitHint = KeyboardHintView(.rightArrow, label: "ms")
    private var footerContent: NSView?
    private var actionGroup: ActionGroupView?

    func searchBar() -> NSView {
        NSLayoutConstraint.activate([
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20)
        ])
        let searchFont = NSFont.systemFont(ofSize: 18)
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.font = searchFont
        searchField.maximumNumberOfLines = 1
        searchField.cell?.wraps = false
        searchField.cell?.isScrollable = false
        searchField.lineBreakMode = .byTruncatingTail
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search apps, actions, calculate, or translate…",
            attributes: [.font: searchFont, .foregroundColor: NSColor.secondaryLabelColor]
        )
        searchField.textColor = .labelColor
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.setAccessibilityLabel("Search applications, actions, calculate, or translate")
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
            searchField.heightAnchor.constraint(lessThanOrEqualToConstant: 22),
            searchField.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 0.5)
        ])
        return bar
    }

    func footer() -> NSView {
        navigation.setAccessibilityLabel("Use the Up and Down arrow keys to navigate")
        precisionControls.isHidden = true
        roundingModeButton.isHidden = true
        timestampUnitHint.isHidden = true
        colorFormatControls.isHidden = true
        colorModeButton.isHidden = true
        numberBaseControls.isHidden = true
        numberBaseModeButton.isHidden = true
        translationExitButton.isHidden = true
        (translationExitButton as? LauncherOpenButton)?.updateTitle("Exit", hint: .escape)
        translationExitButton.setAccessibilityLabel("Exit translation mode")
        translationExitButton.toolTip = "Return to search (Escape)"
        let actions = Appearance.actionGroup(content: Appearance.stack(
            [openButton, translationExitButton, navigation, precisionControls, roundingModeButton, timestampUnitHint,
             colorFormatControls, colorModeButton, numberBaseControls, numberBaseModeButton], spacing: 16))
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

    func updateActionTitle(_ title: String, hint: KeyboardHint = .returnKey) {
        animateActionLayout {
            (openButton as? LauncherOpenButton)?.updateTitle(title, hint: hint)
        }
    }

    func setCalculatorMode(_ isCalculator: Bool, isColor: Bool = false, isTranslation: Bool = false) {
        animateActionLayout {
            navigation.isHidden = isCalculator || isTranslation
        }
        searchIcon.setCalculatorMode(isCalculator, isColor: isColor, isTranslation: isTranslation)
    }

    func setTranslationMode(_ enabled: Bool) {
        guard translationExitButton.isHidden == enabled else { return }
        animateActionLayout { translationExitButton.isHidden = !enabled }
        searchField.setAccessibilityLabel(enabled ? "Text to translate" : "Search applications, actions, calculate, or translate")
        searchField.placeholderString = enabled ? "Text to translate…" : "Search apps, actions, calculate, or translate…"
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
        (roundingModeButton as? LauncherModeButton)?.update(isRounding: isRounding)
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

    func performAfterKeyRelease(_ key: KeyboardHint, action: @escaping () -> Void) {
        let hints = [
            (roundingModeButton as? LauncherModeButton)?.content,
            (colorModeButton as? LauncherModeButton)?.content,
            (numberBaseModeButton as? LauncherModeButton)?.content,
            previousColorFormat, nextColorFormat, previousNumberBase, nextNumberBase, timestampUnitHint
        ].compactMap { $0 }
        guard let hint = hints.first(where: { $0.hint == key && !$0.isHiddenOrHasHiddenAncestor }) else {
            action()
            return
        }
        hint.performAfterKeyRelease(action)
    }

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

    func setColorFormatSwitching(_ format: ColorConversion.Format?, isEnabled: Bool) {
        animateActionLayout {
            configureColorFormatSwitching(format, isEnabled: isEnabled)
        }
    }

    private func configureColorFormatSwitching(_ format: ColorConversion.Format?, isEnabled: Bool) {
        colorModeButton.isHidden = format == nil
        (colorModeButton as? LauncherModeButton)?.update(isSwitchingColors: isEnabled)
        colorFormatControls.isHidden = format == nil || !isEnabled
        guard let format else { return }
        let previous = format.shifted(by: -1).title
        let next = format.shifted(by: 1).title
        if previousColorFormat.label != previous { previousColorFormat.label = previous }
        if nextColorFormat.label != next { nextColorFormat.label = next }
        let help = "Left switches to \(previous); Right switches to \(next). Up edits the color."
        colorFormatControls.setAccessibilityLabel(help)
        colorFormatControls.toolTip = help
    }

    func setNumberBaseSwitching(_ format: NumberBaseConversion.Format?, isEnabled: Bool) {
        animateActionLayout {
            numberBaseModeButton.isHidden = format == nil
            (numberBaseModeButton as? LauncherModeButton)?.update(isSwitchingNumberBases: isEnabled)
            numberBaseControls.isHidden = format == nil || !isEnabled
            guard let format else { return }
            let previous = format.shifted(by: -1).title
            let next = format.shifted(by: 1).title
            if previousNumberBase.label != previous { previousNumberBase.label = previous }
            if nextNumberBase.label != next { nextNumberBase.label = next }
            let help = "Left switches to \(previous); Right switches to \(next). Up edits the number."
            numberBaseControls.setAccessibilityLabel(help)
            numberBaseControls.toolTip = help
        }
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
