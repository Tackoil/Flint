import AppKit

final class CalculatorResultView: NSView {
    private let expressionLabel = Appearance.label("", size: 36, weight: .medium, color: .labelColor)
    private let answerLabel = Appearance.label("", size: 36, weight: .medium, color: .labelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let arrow = Appearance.symbol("arrow.right", size: 20, color: .tertiaryLabelColor)
        for label in [expressionLabel, answerLabel] {
            label.alignment = .center
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        expressionLabel.lineBreakMode = .byTruncatingMiddle
        answerLabel.lineBreakMode = .byTruncatingMiddle
        for item in [arrow, expressionLabel, answerLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        NSLayoutConstraint.activate([
            arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 24),
            arrow.heightAnchor.constraint(equalToConstant: 24),
            expressionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            expressionLabel.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -24),
            expressionLabel.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            expressionLabel.heightAnchor.constraint(equalToConstant: 56),
            answerLabel.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 24),
            answerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            answerLabel.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            answerLabel.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ calculation: NumericCalculation) {
        expressionLabel.stringValue = calculation.formattedExpression
        answerLabel.stringValue = calculation.formattedAnswer()
        setAccessibilityLabel("Calculator: \(calculation.expression). \(calculation.answer)")
        toolTip = calculation.answer
    }

}
