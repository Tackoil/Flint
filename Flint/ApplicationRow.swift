import AppKit

final class ApplicationRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        NSColor.labelColor.withAlphaComponent(0.075).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

final class ApplicationRowContent: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("Application")
    private let appIcon = NSImageView()
    private let nameLabel = Appearance.label("", size: 15, weight: .medium, color: Appearance.text)
    private let kindLabel = Appearance.label("Application", size: 12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.widthAnchor.constraint(equalToConstant: LauncherLayout.applicationIconSize).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: LauncherLayout.applicationIconSize).isActive = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = Appearance.stack([appIcon, nameLabel, Appearance.spacer(), kindLabel], spacing: LauncherLayout.rowSpacing)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LauncherLayout.rowHorizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LauncherLayout.contentInset),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(application: ApplicationRecord, icon: NSImage, selected: Bool) {
        nameLabel.stringValue = application.name
        appIcon.image = icon
        setAccessibilityLabel(application.name)
        updateSelection(selected)
    }

    func updateSelection(_ selected: Bool) {
        kindLabel.textColor = selected ? .labelColor : Appearance.muted
    }
}
