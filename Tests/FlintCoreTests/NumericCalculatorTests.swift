import Foundation
import Testing
@testable import FlintCore

struct NumericCalculatorTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test(arguments: [
        ("(12+8)*5", "(12 + 8) × 5"), ("-5+2", "−5 + 2"), ("2*-3", "2 × −3"),
        ("6x7", "6 × 7"), ("6X7", "6 × 7"), ("18/3", "18 ÷ 3"),
        ("2^-3", "2 ^ −3"), ("1e-3+2", "1e−3 + 2"), ("200 * 15 %", "200 × 15%")
    ])
    func expressionUsesMathSymbolsAndSpacing(example: (String, String)) throws {
        let calculation = try #require(NumericCalculator.evaluate(example.0, locale: locale))
        #expect(calculation.formattedExpression == example.1)
        #expect(calculation.expression == example.0)
    }

    @Test(arguments: [
        ("2 + 3 * 4", "14"), ("(2 + 3) * 4", "20"), ("18 / 3 / 2", "3"),
        ("10 - 3 - 2", "5"), ("-5 + 2", "-3"), ("2 * -3", "-6"),
        ("0.1 + 0.2", "0.3"), (".5 + .25", "0.75"), ("1. / 4", "0.25"),
        ("2^3^2", "512"), ("-2^2", "-4"), ("(-2)^2", "4"), ("2^-3", "0.125"),
        ("9^0.5", "3"), ("0^0", "1"), ("200 * 15%", "30"), ("(25 + 25)%", "0.5"),
        ("−12 ÷ 3 × 2", "-8"), ("6x7", "42"), ("1e3 + 2.5E-1", "1000.25"),
        (" 40 + 2 \n", "42"), ("3 - 3", "0"), ("15%", "0.15"),
        ("-(2+3)", "-5"), ("9007199254740993 + 2", "9007199254740995")
    ])
    func arithmetic(example: (String, String)) throws {
        let calculation = try #require(NumericCalculator.evaluate(example.0, locale: locale))
        let expected = try #require(Decimal(string: example.1, locale: locale))
        #expect(calculation.value == expected)
    }

    @Test(arguments: ["", " \n", "Finder", "1Password", "3D Viewer", "eject", "2 usd", "sin(2)", "2;3", "2 + print(3)"])
    func ordinarySearchRemainsAvailable(query: String) {
        #expect(NumericCalculator.evaluate(query, locale: locale) == nil)
    }

    @Test(arguments: ["3", " 42 \n", "3.5", ".5", "-3", "−3", "+3", "-0", "--3", "(3)", "(-3)",
                      "((3))", "1e3", "1e-3", "-1E+3", "3f"])
    func standaloneNumbersStayInSearch(query: String) {
        #expect(NumericCalculator.evaluate(query, locale: locale) == nil)
    }

    @Test(arguments: ["1 +", "(2 * 3", "2^", "1e-", "2 / -"])
    func unfinishedInputStaysInSearch(query: String) {
        #expect(NumericCalculator.evaluate(query, locale: locale) == nil)
    }

    @Test(arguments: ["1..2+3", "2 3", "2+*3", "(2+3))", "() + 1", "2(3)", "1e2.3"])
    func malformedExpressionsStayInSearch(query: String) {
        #expect(NumericCalculator.evaluate(query, locale: locale) == nil)
    }

    @Test(arguments: ["1/0", "0/0", "2/(3-3)", "0^-1"])
    func divisionByZeroStaysInSearch(query: String) {
        #expect(NumericCalculator.evaluate(query, locale: locale) == nil)
    }

    @Test(arguments: ["1e9999", "10^1024", "(-1)^0.5", "1e-9999"])
    func unrepresentableResultsStayInSearch(query: String) {
        #expect(NumericCalculator.evaluate(query, locale: locale) == nil)
    }

    @Test func boundedInputAndNesting() {
        let long = String(repeating: "1+", count: 600) + "1"
        let nested = String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)
        #expect(NumericCalculator.evaluate(long, locale: locale) == nil)
        #expect(NumericCalculator.evaluate(nested, locale: locale) == nil)
    }

    @Test func localeControlsDecimalInputAndResultFormatting() throws {
        let german = Locale(identifier: "de_DE")
        let calculation = try #require(NumericCalculator.evaluate("1234,5 + 0,25", locale: german))
        #expect(calculation.answer == "1234.75")
        #expect(calculation.formattedAnswer(locale: german) == "1.234,75")
        #expect(calculation.formattedAnswer(locale: Locale(identifier: "en_US")) == "1,234.75")
        #expect(NumericCalculator.evaluate("1234,5", locale: german) == nil)
    }

    @Test func repeatingFractionsRetainUsefulPrecision() throws {
        let calculation = try #require(NumericCalculator.evaluate("1 / 3", locale: locale))
        let value = calculation.value
        #expect(abs(value - Decimal(string: "0.33333333333333333333333333333333333333")!) < Decimal(string: "1e-36")!)
    }
}
