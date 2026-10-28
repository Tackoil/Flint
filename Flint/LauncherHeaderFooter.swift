import AppKit

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
    override var isEnabled: Bool {
        didSet { subviews.first?.alphaValue = isEnabled ? 1 : 0.4 }
    }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setAccessibilityLabel("Open Application")
        toolTip = "Open selected application (Return)"
        let content = Appearance.stack([
            Appearance.label("Open Application", size: 12, color: .labelColor),
            Appearance.keycap("↵")
        ], spacing: 8)
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

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: -5, dy: 0), xRadius: 12, yRadius: 12).fill()
        }
        super.draw(dirtyRect)
    }
}

final class LauncherHeaderFooter {
    static let searchBarHeight: CGFloat = LauncherLayout.cornerRadius * 2
    let searchField = NSTextField()
    let openButton: NSButton = LauncherOpenButton()
    let settingsButton = Appearance.button("")

    func searchBar() -> NSView {
        let icon = Appearance.symbol("magnifyingglass", size: 16, color: .secondaryLabelColor)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20)
        ])
        let searchFont = NSFont.systemFont(ofSize: 18)
        searchField.font = searchFont
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search applications…",
            attributes: [.font: searchFont, .foregroundColor: NSColor.secondaryLabelColor]
        )
        searchField.textColor = .labelColor
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.setAccessibilityLabel("Search applications")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return searchBarLayout(icon: icon)
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
        let navigation = Appearance.stack([
            Appearance.label("Navigate", size: 12), Appearance.keycap("↑"), Appearance.keycap("↓")
        ], spacing: 4)
        navigation.setAccessibilityLabel("Use the Up and Down arrow keys to navigate")
        let actions = Appearance.actionGroup(content: Appearance.stack([openButton, navigation], spacing: 16))
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
        return inset(Appearance.stack([settingsButton, Appearance.spacer(), actions], spacing: 13),
                     horizontal: LauncherLayout.floatingControlInset, height: LauncherLayout.footerHeight)
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
