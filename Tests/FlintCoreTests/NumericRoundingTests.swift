import Foundation
import Testing
@testable import FlintCore

struct NumericRoundingTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test(arguments: [
        ("123.456+0", 2, "123.46"), ("123.456+0", 0, "123"), ("123.456+0", -1, "120"),
        ("-123.456+0", 1, "-123.5"), ("0.00123456+0", 5, "0.00123"),
        ("999.5+0", -1, "1000"), ("1.25+0", 1, "1.3"), ("-1.25+0", 1, "-1.3"),
        ("12345+0", -2, "12300"), ("0+0", 0, "0"), ("1e-100+0", 100, "1e-100"),
        ("9.999e127+0", -126, "10e127")
    ])
    func roundsUsingDecimalPlaces(example: (String, Int, String)) throws {
        var calculation = try #require(NumericCalculator.evaluate(example.0, locale: locale))
        let original = calculation.value
        calculation.adjustPrecision(by: example.1 - calculation.decimalPlaceCount)
        let copied = try #require(NumericCalculator.evaluate(calculation.answer + "+0", locale: locale)).value
        let expected = try #require(Decimal(string: example.2, locale: locale))
        #expect(copied == expected)
        #expect(calculation.decimalPlaceCount == example.1)
        #expect(calculation.value == original)
    }

    @Test func increasingPrecisionRestoresOriginalDigits() throws {
        var calculation = try #require(NumericCalculator.evaluate("123.456+0", locale: locale))
        calculation.adjustPrecision(by: -2)
        #expect(calculation.answer == "123.5")
        calculation.adjustPrecision(by: -1)
        #expect(calculation.answer == "123")
        calculation.adjustPrecision(by: 1)
        #expect(calculation.answer == "123.5")
        calculation.adjustPrecision(by: 100)
        #expect(calculation.answer == "123.456")
        #expect(calculation.selectedDecimalPlaces == nil)
        calculation.adjustPrecision(by: -100)
        #expect(calculation.answer == "1E+2" && calculation.decimalPlaceCount == -2)
    }

    @Test func localizedDisplayAndClipboardRepresentTheSameRoundedValue() throws {
        var calculation = try #require(NumericCalculator.evaluate("1234.567+0", locale: locale))
        calculation.adjustPrecision(by: -1)
        #expect(calculation.answer == "1234.57")
        #expect(calculation.formattedAnswer(locale: Locale(identifier: "de_DE")) == "1.234,57…")
    }

    @Test func freshCalculationsDefaultToTenDecimalPlaces() throws {
        var calculation = try #require(NumericCalculator.evaluate("1/3", locale: locale))
        #expect(calculation.decimalPlaceCount == 10 && calculation.answer == "0.3333333333")
        #expect(calculation.formattedAnswer(locale: locale) == "0.3333333333…")
        calculation.adjustPrecision(by: -7)
        #expect(calculation.answer == "0.333")
        let fresh = try #require(NumericCalculator.evaluate("1/3", locale: locale))
        #expect(fresh.selectedDecimalPlaces == nil && fresh.answer.count > calculation.answer.count)
    }

    @Test(arguments: [("123.456+0", -2), ("1/3", 3), ("12345+0", -2)])
    func resetPrecisionRestoresDefaultPreview(example: (String, Int)) throws {
        var calculation = try #require(NumericCalculator.evaluate(example.0, locale: locale))
        let original = calculation
        calculation.adjustPrecision(by: example.1)
        #expect(calculation.selectedDecimalPlaces != nil)
        calculation.resetPrecision()
        #expect(calculation == original)
        #expect(calculation.answer == original.answer)
        #expect(calculation.formattedAnswer(locale: locale) == original.formattedAnswer(locale: locale))
    }

    @Test func rightArrowRevealsMoreDigitsAndEventuallyRemovesMarker() throws {
        var calculation = try #require(NumericCalculator.evaluate("3^(-1/2)", locale: locale))
        #expect(calculation.formattedAnswer(locale: locale) == "0.5773502692…")
        #expect(calculation.answer == "0.5773502692")
        calculation.adjustPrecision(by: 1)
        #expect(calculation.formattedAnswer(locale: locale) == "0.57735026919…")
        calculation.adjustPrecision(by: 1)
        #expect(calculation.formattedAnswer(locale: locale) == "0.577350269190…")
        calculation.adjustPrecision(by: 100)
        #expect(!calculation.hasMoreFractionalDigits)
        #expect(!calculation.formattedAnswer(locale: locale).contains("…"))
        #expect(calculation.answer == NSDecimalNumber(decimal: calculation.value).stringValue)
    }

    @Test func shortFractionsAndIntegersHaveNoContinuationMarker() throws {
        for query in ["1/4", "0.1+0.2", "2+2", "0+0"] {
            let calculation = try #require(NumericCalculator.evaluate(query, locale: locale))
            #expect(!calculation.hasMoreFractionalDigits)
            #expect(!calculation.formattedAnswer(locale: locale).contains("…"))
        }
    }

    @Test func hiddenDigitsAreMarkedEvenWhenTheyRoundToZero() throws {
        let tiny = try #require(NumericCalculator.evaluate("1e-100+0", locale: locale))
        #expect(tiny.answer == "0.0000000000")
        #expect(tiny.formattedAnswer(locale: locale) == "0.0000000000…")
        var carry = try #require(NumericCalculator.evaluate("1.999+0", locale: locale))
        carry.adjustPrecision(by: -1)
        #expect(carry.answer == "2.00")
        #expect(carry.formattedAnswer(locale: locale) == "2.00…")
    }
}
