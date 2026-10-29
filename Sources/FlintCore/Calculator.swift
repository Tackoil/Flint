import Foundation

enum CalculatorResult: Equatable, Sendable {
    case numeric(NumericCalculation)
    case timestamp(TimestampCalculation)
    case color(ColorConversion)

    var decimalPlaceCount: Int? {
        guard case .numeric(let calculation) = self else { return nil }
        return calculation.decimalPlaceCount
    }

    var answer: String {
        switch self {
        case .numeric(let calculation): return calculation.answer
        case .timestamp(let calculation): return calculation.answer
        case .color(let conversion): return conversion.answer
        }
    }
}

enum Calculator {
    static func evaluate(_ query: String, locale: Locale = .current,
                         timestampUnit: TimestampCalculation.Unit = .seconds,
                         colorFormat: ColorConversion.Format? = nil) -> CalculatorResult? {
        if let color = ColorConversion.evaluate(query, outputFormat: colorFormat) { return .color(color) }
        if let timestamp = TimestampCalculation.evaluate(query, outputUnit: timestampUnit) { return .timestamp(timestamp) }
        return NumericCalculator.evaluate(query, locale: locale).map(CalculatorResult.numeric)
    }
}
