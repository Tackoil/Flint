import Foundation

struct NumericCalculation: Equatable, Sendable {
    let expression: String
    let value: Decimal

    var answer: String { NSDecimalNumber(decimal: value).stringValue }

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
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 128
        formatter.maximumSignificantDigits = 38
        formatter.usesSignificantDigits = true
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? answer
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
