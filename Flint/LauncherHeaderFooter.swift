import AppKit

final class LauncherHeaderFooter {
    let searchField = NSTextField()
    let countLabel = Appearance.label("", size: 11)
    let pathLabel = Appearance.label("", size: 11)
    let refreshButton = Appearance.button("Refresh  ⌘R")
    let dismissButton = Appearance.button("esc")
    let openButton = Appearance.button("Open Application  ↵")
    let settingsButton = Appearance.button("")

    func searchBar() -> NSView {
        let icon = Appearance.symbol("magnifyingglass", size: 21, color: NSColor(white: 0.6, alpha: 1))
        icon.widthAnchor.constraint(equalToConstant: 25).isActive = true
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search applications…",
            attributes: [.foregroundColor: NSColor(white: 0.44, alpha: 1)]
        )
        searchField.font = .systemFont(ofSize: 23)
        searchField.textColor = Appearance.text
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.setAccessibilityLabel("Search applications")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dismissButton.wantsLayer = true
        dismissButton.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        dismissButton.layer?.cornerRadius = 5
        dismissButton.widthAnchor.constraint(equalToConstant: 31).isActive = true
        dismissButton.heightAnchor.constraint(equalToConstant: 23).isActive = true
        dismissButton.setAccessibilityLabel("Hide launcher")
        return inset(Appearance.stack([icon, searchField, dismissButton], spacing: 15), horizontal: 25, height: 83)
    }

    func sectionBar() -> NSView {
        let icon = Appearance.symbol("square.grid.2x2.fill", size: 12, color: Appearance.accent)
        let title = Appearance.label("Applications", size: 12, weight: .semibold, color: NSColor(white: 0.75, alpha: 1))
        return inset(Appearance.stack([icon, title, countLabel, Appearance.spacer(), refreshButton]), horizontal: 25, height: 43)
    }

    func selectionBar() -> NSView {
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return inset(Appearance.stack([pathLabel, Appearance.spacer()]), horizontal: 26, height: 27)
    }

    func footer() -> NSView {
        let flame = Appearance.symbol("flame.fill", size: 14, color: Appearance.accent)
        let brand = Appearance.label("flint", size: 13, weight: .semibold, color: NSColor(white: 0.73, alpha: 1))
        let navigation = Appearance.stack([
            Appearance.keycap("↑"), Appearance.keycap("↓"), Appearance.label("Navigate", size: 11)
        ], spacing: 4)
        openButton.contentTintColor = NSColor(white: 0.8, alpha: 1)
        openButton.font = .systemFont(ofSize: 11, weight: .medium)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.toolTip = "Settings (⌘,)"
        settingsButton.setAccessibilityLabel("Settings")
        settingsButton.widthAnchor.constraint(equalToConstant: 25).isActive = true
        return inset(Appearance.stack([flame, brand, settingsButton, Appearance.spacer(), navigation, openButton], spacing: 13), horizontal: 25, height: 48)
    }

    private func inset(_ content: NSView, horizontal: CGFloat, height: CGFloat) -> NSView {
        let container = NSView()
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
