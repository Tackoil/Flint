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
    private lazy var iconWidth = appIcon.widthAnchor.constraint(equalToConstant: LauncherLayout.applicationIconSize)
    private lazy var iconHeight = appIcon.heightAnchor.constraint(equalToConstant: LauncherLayout.applicationIconSize)
    private let nameLabel = Appearance.label("", size: 15, weight: .medium, color: Appearance.text)
    private let kindLabel = Appearance.label("Application", size: 12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        let iconSlot = NSView()
        iconSlot.addSubview(appIcon)
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconSlot.widthAnchor.constraint(equalToConstant: LauncherLayout.applicationIconSize),
            iconSlot.heightAnchor.constraint(equalToConstant: LauncherLayout.applicationIconSize),
            appIcon.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            appIcon.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            iconWidth, iconHeight
        ])
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = Appearance.stack([iconSlot, nameLabel, Appearance.spacer(), kindLabel], spacing: LauncherLayout.rowSpacing)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LauncherLayout.rowHorizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LauncherLayout.contentInset),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(item: LauncherItem, icon: NSImage, selected: Bool) {
        nameLabel.stringValue = item.name
        kindLabel.stringValue = item.kind
        appIcon.image = icon
        let iconSize: CGFloat
        if case .action = item {
            iconSize = LauncherLayout.actionIconSize
        } else {
            iconSize = LauncherLayout.applicationIconSize
        }
        iconWidth.constant = iconSize
        iconHeight.constant = iconSize
        setAccessibilityLabel("\(item.name), \(item.kind)")
        updateSelection(selected)
    }

    func updateSelection(_ selected: Bool) {
        kindLabel.textColor = selected ? .labelColor : Appearance.muted
    }
}
