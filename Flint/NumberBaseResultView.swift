import AppKit

final class NumberBaseRowView: NSView {
    private let titleLabel = Appearance.label("", size: 12, weight: .medium, color: .secondaryLabelColor)
    private let valueLabel = Appearance.label("", size: 22, weight: .medium, color: .labelColor)
    private(set) var format = NumberBaseConversion.Format.decimal
    private(set) var isSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in [titleLabel, valueLabel] {
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 44),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ conversion: NumberBaseConversion, format: NumberBaseConversion.Format) {
        self.format = format
        isSelected = format == conversion.format
        titleLabel.stringValue = format.title
        valueLabel.stringValue = conversion.value(in: format, grouped: true)
        valueLabel.toolTip = conversion.value(in: format)
        alphaValue = isSelected ? 1 : 0.4
        setAccessibilityLabel("\(format.title): \(conversion.value(in: format))\(isSelected ? ", selected" : "")")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let font = NSFont.monospacedSystemFont(ofSize: 22, weight: .medium)
        let width = (valueLabel.stringValue as NSString).size(withAttributes: [.font: font]).width
        let size = min(22, 22 * max(1, valueLabel.bounds.width - 8) / max(1, width))
        valueLabel.font = .monospacedSystemFont(ofSize: size, weight: .medium)
    }
}

final class NumberBaseResultView: NSView {
    private let rows = NumberBaseConversion.Format.allCases.map { _ in NumberBaseRowView() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ conversion: NumberBaseConversion) {
        for (row, format) in zip(rows, NumberBaseConversion.Format.allCases) {
            row.configure(conversion, format: format)
        }
        setAccessibilityLabel("Number base conversion: \(conversion.expression). Selected \(conversion.format.title): \(conversion.answer)")
        toolTip = conversion.answer
    }
}
