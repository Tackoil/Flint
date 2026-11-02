import Foundation

enum CalculatorResult: Equatable, Sendable {
    case numeric(NumericCalculation)
    case timestamp(TimestampCalculation)
    case color(ColorConversion)
    case numberBase(NumberBaseConversion)

    var decimalPlaceCount: Int? {
        guard case .numeric(let calculation) = self else { return nil }
        return calculation.decimalPlaceCount
    }

    var answer: String {
        switch self {
        case .numeric(let calculation): return calculation.answer
        case .timestamp(let calculation): return calculation.answer
        case .color(let conversion): return conversion.answer
        case .numberBase(let conversion): return conversion.answer
        }
    }
}

enum Calculator {
    static func evaluate(_ query: String, locale: Locale = .current,
                         timestampUnit: TimestampCalculation.Unit = .seconds,
                         colorFormat: ColorConversion.Format? = nil,
                         numberBaseFormat: NumberBaseConversion.Format? = nil) -> CalculatorResult? {
        #if !FLINT_CUSTOM_FEATURES || FLINT_NUMBER_BASES
        if let number = NumberBaseConversion.evaluate(query, outputFormat: numberBaseFormat) { return .numberBase(number) }
        #endif
        if NumberBaseConversion.hasExplicitPrefix(query) { return nil }
        #if !FLINT_CUSTOM_FEATURES || FLINT_COLORS
        if let color = ColorConversion.evaluate(query, outputFormat: colorFormat) { return .color(color) }
        #endif
        #if !FLINT_CUSTOM_FEATURES || FLINT_TIMESTAMPS
        if let timestamp = TimestampCalculation.evaluate(query, outputUnit: timestampUnit) { return .timestamp(timestamp) }
        #endif
        #if !FLINT_CUSTOM_FEATURES || FLINT_CALCULATOR
        return NumericCalculator.evaluate(query, locale: locale).map(CalculatorResult.numeric)
        #else
        return nil
        #endif
    }
}
