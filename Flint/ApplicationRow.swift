import AppKit

final class ApplicationRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor(white: 1, alpha: 0.075).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.07).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

final class ApplicationRowContent: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("Application")
    private let appIcon = NSImageView()
    private let nameLabel = Appearance.label("", size: 15, weight: .medium, color: Appearance.text)
    private let kindLabel = Appearance.label("Application", size: 12)
    private let returnKey = Appearance.keycap("↵")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = Appearance.stack([appIcon, nameLabel, Appearance.spacer(), kindLabel, returnKey], spacing: 13)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
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
        returnKey.isHidden = !selected
        kindLabel.textColor = selected ? NSColor(white: 0.65, alpha: 1) : Appearance.muted
    }
}
