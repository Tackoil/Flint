import Foundation
import Testing
@testable import FlintCore

struct NumericNotationTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test(arguments: [
        ("12345+0", -2, "1.23E+4"), ("-12345+0", -2, "-1.23E+4"),
        ("1234.56+0", 0, "1235"), ("1234.56+0", -1, "1.23E+3"),
        ("999.5+0", -1, "1.00E+3"), ("100+0", -1, "1.0E+2"), ("100+0", -2, "1E+2"),
        ("0.00123456+0", 5, "0.00123"), ("0.000000123456+0", 9, "0.000000123"),
        ("0+0", 0, "0"), ("1e100+0", -98, "1.00E+100"), ("10e127+0", -126, "1.00E+128")
    ])
    func scientificNotationRequiresFewerFiguresThanIntegerDigits(example: (String, Int, String)) throws {
        var calculation = try #require(NumericCalculator.evaluate(example.0, locale: locale))
        calculation.adjustPrecision(by: example.1 - calculation.decimalPlaceCount)
        #expect(calculation.answer == example.2)
        let copied = try #require(NumericCalculator.evaluate(calculation.answer + "+0", locale: locale))
        #expect(!copied.value.isNaN)
    }

    @Test func fullIntegerPrecisionStaysDecimal() throws {
        let calculation = try #require(NumericCalculator.evaluate("12345+0", locale: locale))
        #expect(calculation.answer == "12345")
        #expect(calculation.formattedAnswer(locale: Locale(identifier: "en_US")) == "12,345")
        let large = try #require(NumericCalculator.evaluate("1e100+0", locale: locale))
        #expect(large.answer == "1E+100")
    }

    @Test func restoringPrecisionReturnsToDecimal() throws {
        var calculation = try #require(NumericCalculator.evaluate("12345.67+0", locale: locale))
        calculation.adjustPrecision(by: -4)
        #expect(calculation.answer == "1.23E+4")
        calculation.adjustPrecision(by: 2)
        #expect(calculation.answer == "12346")
        calculation.adjustPrecision(by: 2)
        #expect(calculation.answer == "12345.67")
    }

    @Test func localizedScientificDisplayMatchesPortableClipboardNotation() throws {
        var calculation = try #require(NumericCalculator.evaluate("12345+0", locale: locale))
        calculation.adjustPrecision(by: -2)
        #expect(calculation.formattedAnswer(locale: Locale(identifier: "de_DE")) == "1,23E+4")
        #expect(calculation.answer == "1.23E+4")
    }

    @Test(arguments: [("1E+128+0", "10e127"), ("1.234E+128+0", "12.34e127")])
    func copiedLargeExponentsRemainUsable(example: (String, String)) throws {
        let calculation = try #require(NumericCalculator.evaluate(example.0, locale: locale))
        #expect(calculation.value == Decimal(string: example.1, locale: locale))
        let copied = try #require(NumericCalculator.evaluate(calculation.answer + "+0", locale: locale))
        #expect(copied.value == calculation.value)
        #expect(NumericCalculator.evaluate("1E+166+0", locale: locale) == nil)
    }
}
