import Foundation

struct NumericCalculation: Equatable, Sendable {
    let expression: String
    let value: Decimal
    private(set) var selectedDecimalPlaces: Int?

    var answer: String {
        scientificAnswer(locale: Locale(identifier: "en_US_POSIX"))
            ?? decimalAnswer
    }

    var decimalPlaceCount: Int { selectedDecimalPlaces ?? min(10, maximumDecimalPlaces) }

    var hasMoreFractionalDigits: Bool { decimalPlaceCount >= 0 && roundedValue != value }

    private var maximumDecimalPlaces: Int {
        NSDecimalNumber(decimal: value).stringValue.split(separator: ".").dropFirst().first?.count ?? 0
    }

    private var significantFigureCount: Int {
        min(maximumSignificantFigures, max(1, magnitude(of: roundedValue) + 1 + decimalPlaceCount))
    }

    private var maximumSignificantFigures: Int {
        let digits = NSDecimalNumber(decimal: value).stringValue.filter { $0.isNumber }.drop { $0 == "0" }
        return min(38, max(1, digits.count))
    }

    private var roundedValue: Decimal {
        rounded(to: decimalPlaceCount)
    }

    private var decimalAnswer: String {
        var text = NSDecimalNumber(decimal: roundedValue).stringValue
        guard hasMoreFractionalDigits, decimalPlaceCount > 0 else { return text }
        let places = text.split(separator: ".").dropFirst().first?.count ?? 0
        if places == 0 { text += "." }
        return text + String(repeating: "0", count: max(0, decimalPlaceCount - places))
    }

    mutating func adjustPrecision(by offset: Int) {
        let minimum = -max(0, magnitude(of: value))
        let places = min(maximumDecimalPlaces, max(minimum, decimalPlaceCount + offset))
        guard !rounded(to: places).isNaN else { return }
        selectedDecimalPlaces = places == min(10, maximumDecimalPlaces) ? nil : places
    }

    mutating func resetPrecision() {
        selectedDecimalPlaces = nil
    }

    private func rounded(to places: Int) -> Decimal {
        var original = value
        var result = Decimal()
        NSDecimalRound(&result, &original, places, .plain)
        return result
    }

    private func magnitude(of number: Decimal) -> Int {
        guard number != 0 else { return 0 }
        let digits = NSDecimalNumber(decimal: abs(number).significand).stringValue.count
        return digits - 1 + number.exponent
    }

    var formattedExpression: String {
        let symbols = ["*": "×", "x": "×", "X": "×", "/": "÷", "-": "−"]
        var text = expression.map { symbols[String($0)] ?? String($0) }.joined()
        let rules = [
            (#"\s*([+−×÷^])\s*"#, " $1 "),
            (#"\(\s*"#, "("), (#"\s*\)"#, ")"), (#"\s*%"#, "%")
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"(^|[(+−×÷^]\s*)[ ]*([+−])\s+"#,
                                         with: "$1$2", options: .regularExpression)
        return text.replacingOccurrences(of: #"([0-9][eE])\s*([+−])\s*"#,
                                        with: "$1$2", options: .regularExpression)
    }

    func formattedAnswer(locale: Locale = .current) -> String {
        if let scientific = scientificAnswer(locale: locale) { return scientific }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = max(0, decimalPlaceCount)
        formatter.minimumFractionDigits = hasMoreFractionalDigits ? max(0, decimalPlaceCount) : 0
        let text = formatter.string(from: NSDecimalNumber(decimal: roundedValue)) ?? answer
        return text + (hasMoreFractionalDigits ? "…" : "")
    }

    private func scientificAnswer(locale: Locale) -> String? {
        let number = roundedValue
        guard number != 0 else { return nil }
        var digits = NSDecimalNumber(decimal: abs(number).significand).stringValue
        let exponent = digits.count - 1 + number.exponent
        guard significantFigureCount < exponent + 1 else { return nil }
        while digits.last == "0" { digits.removeLast() }
        if selectedDecimalPlaces != nil {
            digits += String(repeating: "0", count: max(0, significantFigureCount - digits.count))
        }
        let first = digits.removeFirst()
        let fraction = digits.isEmpty ? "" : (locale.decimalSeparator ?? ".") + digits
        let sign = number < 0 ? "-" : ""
        return "\(sign)\(first)\(fraction)E+\(exponent)"
    }
}

enum NumericCalculator {
    static func evaluate(_ query: String, locale: Locale = .current) -> NumericCalculation? {
        let expression = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = expression.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard normalized.count <= 1_024, isNumericExpression(normalized) else { return nil }
        do {
            var parser = try NumericExpressionParser(normalized)
            let value = try parser.evaluate()
            guard parser.hasOperation else { return nil }
            return NumericCalculation(expression: expression, value: value)
        } catch {
            return nil
        }
    }

    private static func isNumericExpression(_ expression: String) -> Bool {
        let allowed = Set("0123456789.eExX+-−*/×÷^%()")
        return expression.contains(where: { "0123456789".contains($0) })
            && expression.allSatisfy { allowed.contains($0) || $0.isWhitespace }
    }
}

enum NumericCalculationError: Error {
    case incomplete, invalid, divisionByZero, outOfRange, tooLong
}
