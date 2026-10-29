import AppKit

final class CalculatorResultView: NSView {
    private let colorView = ColorResultView()
    private let numberBaseView = NumberBaseResultView()
    private var calculationViews: [NSView] = []
    private let expressionLabel = Appearance.label("", size: 36, weight: .medium, color: .labelColor)
    private let answerLabel = Appearance.label("", size: 36, weight: .medium, color: .labelColor)
    private let localTimeLabel = Appearance.label("", size: 12, color: .secondaryLabelColor)
    private let answerTimeLabel = Appearance.label("", size: 12, color: .secondaryLabelColor)
    private let sourceUnitLabel = Appearance.label("", size: 12, color: .secondaryLabelColor)
    private let answerUnitLabel = Appearance.label("", size: 12, color: .secondaryLabelColor)
    private lazy var expressionHeight = expressionLabel.heightAnchor.constraint(equalToConstant: 56)
    private lazy var answerHeight = answerLabel.heightAnchor.constraint(equalToConstant: 56)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let arrow = Appearance.symbol("arrow.right", size: 20, color: .tertiaryLabelColor)
        for label in [expressionLabel, answerLabel, localTimeLabel, answerTimeLabel, sourceUnitLabel, answerUnitLabel] {
            label.alignment = .center
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        expressionLabel.lineBreakMode = .byTruncatingMiddle
        answerLabel.lineBreakMode = .byTruncatingMiddle
        localTimeLabel.lineBreakMode = .byTruncatingMiddle
        localTimeLabel.isHidden = true
        answerTimeLabel.lineBreakMode = .byTruncatingMiddle
        answerTimeLabel.isHidden = true
        sourceUnitLabel.isHidden = true
        answerUnitLabel.toolTip = "Left selects seconds; Right selects milliseconds."
        answerUnitLabel.isHidden = true
        let expression = NSStackView(views: [expressionLabel, localTimeLabel, sourceUnitLabel])
        let answer = NSStackView(views: [answerLabel, answerTimeLabel, answerUnitLabel])
        for stack in [expression, answer] {
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 6
        }
        for item in [arrow, expression, answer] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        calculationViews = [arrow, expression, answer]
        colorView.translatesAutoresizingMaskIntoConstraints = false
        colorView.isHidden = true
        addSubview(colorView)
        numberBaseView.translatesAutoresizingMaskIntoConstraints = false
        numberBaseView.isHidden = true
        addSubview(numberBaseView)
        NSLayoutConstraint.activate([
            numberBaseView.leadingAnchor.constraint(equalTo: leadingAnchor),
            numberBaseView.trailingAnchor.constraint(equalTo: trailingAnchor),
            numberBaseView.topAnchor.constraint(equalTo: topAnchor),
            numberBaseView.bottomAnchor.constraint(equalTo: bottomAnchor),
            colorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            colorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            colorView.topAnchor.constraint(equalTo: topAnchor),
            colorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 24),
            arrow.heightAnchor.constraint(equalToConstant: 24),
            expression.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            expression.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -24),
            expression.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            expressionLabel.widthAnchor.constraint(equalTo: expression.widthAnchor),
            expressionHeight,
            localTimeLabel.widthAnchor.constraint(equalTo: expression.widthAnchor),
            sourceUnitLabel.widthAnchor.constraint(equalTo: expression.widthAnchor),
            answer.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 24),
            answer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            answer.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            answerLabel.widthAnchor.constraint(equalTo: answer.widthAnchor),
            answerTimeLabel.widthAnchor.constraint(equalTo: answer.widthAnchor),
            answerUnitLabel.widthAnchor.constraint(equalTo: answer.widthAnchor),
            answerHeight
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ result: CalculatorResult) {
        let color = colorConversion(from: result)
        let number = numberBaseConversion(from: result)
        colorView.isHidden = color == nil
        numberBaseView.isHidden = number == nil
        calculationViews.forEach { $0.isHidden = color != nil || number != nil }
        if case .numeric(let calculation) = result { configureNumeric(calculation) }
        if case .timestamp(let calculation) = result { configureTimestamp(calculation) }
        if let color { configureColor(color) }
        if let number {
            numberBaseView.configure(number)
            setAccessibilityLabel(numberBaseView.accessibilityLabel())
            toolTip = number.answer
        }
    }

    private func numberBaseConversion(from result: CalculatorResult) -> NumberBaseConversion? {
        guard case .numberBase(let number) = result else { return nil }
        return number
    }

    private func configureNumeric(_ calculation: NumericCalculation) {
        expressionLabel.stringValue = calculation.formattedExpression
        answerLabel.stringValue = calculation.formattedAnswer()
        expressionLabel.font = .systemFont(ofSize: 36, weight: .medium)
        expressionHeight.constant = 56
        answerLabel.font = .systemFont(ofSize: 36, weight: .medium)
        answerHeight.constant = 56
        localTimeLabel.isHidden = true
        answerTimeLabel.isHidden = true
        sourceUnitLabel.isHidden = true
        answerUnitLabel.isHidden = true
        setAccessibilityLabel("Calculator: \(calculation.expression). \(calculation.answer)")
        toolTip = calculation.answer + (calculation.hasMoreFractionalDigits ? "… Press Right Arrow for more digits." : "")
    }

    private func configureColor(_ conversion: ColorConversion) {
        colorView.configure(conversion)
        setAccessibilityLabel("Color conversion: \(conversion.expression). \(conversion.format.title): \(conversion.answer)")
        toolTip = conversion.answer
    }

    private func colorConversion(from result: CalculatorResult) -> ColorConversion? {
        guard case .color(let color) = result else { return nil }
        return color
    }

    private func configureTimestamp(_ calculation: TimestampCalculation) {
        let fromUnix = calculation.direction == .unixToZulu
        let zuluSize: CGFloat = calculation.zuluTimestamp.count > 24 ? 16 : 18
        let unixSize: CGFloat = calculation.unixValue.count > 14 ? 24 : 36
        let unixHeight: CGFloat = unixSize == 36 ? 44 : 30
        expressionLabel.stringValue = fromUnix ? calculation.unixValue : calculation.expression
        expressionLabel.font = .systemFont(ofSize: fromUnix ? unixSize : zuluSize, weight: .medium)
        expressionHeight.constant = fromUnix ? unixHeight : 24
        answerLabel.stringValue = calculation.answer
        answerLabel.font = .systemFont(ofSize: fromUnix ? zuluSize : unixSize, weight: .medium)
        answerHeight.constant = fromUnix ? 24 : unixHeight
        localTimeLabel.stringValue = calculation.localTimeHint()
        localTimeLabel.toolTip = localTimeLabel.stringValue
        localTimeLabel.isHidden = fromUnix
        answerTimeLabel.stringValue = localTimeLabel.stringValue
        answerTimeLabel.toolTip = answerTimeLabel.stringValue
        answerTimeLabel.isHidden = !fromUnix
        configureUnits(calculation)
        let description = "\(calculation.unit.title): \(calculation.unixValue). Zulu timestamp: \(calculation.zuluTimestamp). Local time: \(localTimeLabel.stringValue)"
        setAccessibilityLabel("Calculator: \(description)")
        toolTip = description
    }

    private func configureUnits(_ calculation: TimestampCalculation) {
        let fromUnix = calculation.direction == .unixToZulu
        sourceUnitLabel.stringValue = calculation.unit.title
        sourceUnitLabel.isHidden = !fromUnix
        answerUnitLabel.stringValue = calculation.unit.title
        answerUnitLabel.isHidden = fromUnix
    }
}
