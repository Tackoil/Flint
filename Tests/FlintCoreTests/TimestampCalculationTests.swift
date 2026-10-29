import Foundation
import Testing
@testable import FlintCore

struct TimestampCalculationTests {
    @Test(arguments: [
        ("2024-03-15T14:30:00Z", "1710513000"),
        ("1970-01-01T00:00:00Z", "0"),
        ("1970-01-01T00:00:00.000000001Z", "0"),
        ("1970-01-01T00:00:00.999999999Z", "0"),
        ("2024-03-15T14:30:00.123456789Z", "1710513000"),
        ("2024-03-15T14:30:00.999999999Z", "1710513000"),
        ("2024-02-29T00:00:00.001Z", "1709164800"),
        (" 2024-03-15T14:30:00Z\n", "1710513000"),
        ("2038-01-19T03:14:08Z", "2147483648"),
        ("9999-12-31T23:59:59Z", "253402300799"),
        ("9999-12-31T23:59:59.999999999Z", "253402300799")
    ])
    func convertsZuluToUnixSeconds(example: (String, String)) throws {
        let result = try #require(Calculator.evaluate(example.0))
        #expect(result.answer == example.1)
        #expect(TimestampCalculation.evaluate(example.0)?.answer == example.1)
    }

    @Test(arguments: [
        "", "Finder", "2024-03-15T", "2024-03-15T14:30:00", "2024-03-15T14:30:00+00:00",
        "2024-03-15T14:30Z", "2024-03-15 14:30:00Z", "2024-03-15t14:30:00z", "2024-02-30T00:00:00Z",
        "2023-02-29T00:00:00Z", "2024-04-31T00:00:00Z", "2024-13-01T00:00:00Z", "2024-00-01T00:00:00Z",
        "2024-03-00T00:00:00Z", "2024-03-15T24:00:00Z", "2024-03-15T14:60:00Z", "2024-03-15T14:30:60Z",
        "2024-03-15T14:30:00.Z", "2024-03-15T14:30:00.1234567890Z", "2024-03-15T14:30:00Z extra",
        "2024-03-15T14:30:00Z\n2024-03-15T14:30:00Z"
    ])
    func invalidTimestampsStayInSearch(query: String) {
        #expect(TimestampCalculation.evaluate(query) == nil)
        #expect(Calculator.evaluate(query) == nil)
    }

    @Test func localHintIncludesDateRolloverFractionAndOffset() throws {
        let result = try #require(TimestampCalculation.evaluate("2024-03-15T20:30:00.123Z"))
        #expect(result.localTimeHint(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
                == "2024-03-16 04:30:00.123 GMT+08:00")
        #expect(result.localTimeHint(timeZone: TimeZone(secondsFromGMT: 0)!)
                == "2024-03-15 20:30:00.123 GMT+00:00")
        #expect(result.answer == "1710534600")
    }

    @Test(arguments: [
        ("2024-03-10T06:59:59Z", "2024-03-10 01:59:59 GMT-05:00"),
        ("2024-03-10T07:00:00Z", "2024-03-10 03:00:00 GMT-04:00")
    ])
    func localHintUsesOffsetAtTheTimestamp(example: (String, String)) throws {
        let result = try #require(TimestampCalculation.evaluate(example.0))
        #expect(result.localTimeHint(timeZone: TimeZone(identifier: "America/New_York")!) == example.1)
    }

    @Test func sharesCalculatorWithoutChangingNumericSearchRules() throws {
        let locale = Locale(identifier: "de_DE")
        #expect(Calculator.evaluate("1234,5 + 0,25", locale: locale)?.answer == "1234.75")
        #expect(Calculator.evaluate("2024-03-15T14:30:00.5Z", locale: locale)?.answer == "1710513000")
        #expect(Calculator.evaluate("3")?.answer == "1970-01-01T00:00:03Z")
        #expect(Calculator.evaluate("3+") == nil)
        #expect(Calculator.evaluate("1/0") == nil)
        #expect(TimestampCalculation.evaluate("2024-03-15") == nil)
        #expect(Calculator.evaluate("2024-03-15")?.answer == "2006")
        let timestamp = try #require(Calculator.evaluate("2024-03-15T14:30:00Z"))
        guard case .timestamp = timestamp else { Issue.record("Expected timestamp calculator result"); return }
    }

    @Test(arguments: [
        ("1710513000", "2024-03-15T14:30:00Z"),
        ("0", "1970-01-01T00:00:00Z"),
        ("  +1710513000\n", "2024-03-15T14:30:00Z"),
        ("2147483648", "2038-01-19T03:14:08Z"),
        ("253402300799", "9999-12-31T23:59:59Z")
    ])
    func convertsUnixSecondsToZulu(example: (String, String)) throws {
        let result = try #require(TimestampCalculation.evaluate(example.0))
        #expect(result.direction == .unixToZulu)
        #expect(result.answer == example.1)
        #expect(Calculator.evaluate(example.0)?.answer == example.1)
        let roundTrip = try #require(TimestampCalculation.evaluate(result.answer))
        #expect(roundTrip.direction == .zuluToUnix)
        #expect(roundTrip.answer == result.unixSeconds)
    }

    @Test(arguments: ["253402300800 s", "253402300800000", "253402300800000 ms", "-62135596801", "999999999999999999999999999999999",
                      "NaN", "inf", "1e3", "1710513000.", "1710513000.1234567890",
                      "1710513000,5", "1 710 513 000", "--1"])
    func rejectsInvalidOrOutOfRangeUnixSeconds(query: String) {
        #expect(TimestampCalculation.evaluate(query) == nil)
    }

    @Test(arguments: ["-1", "-0.5", "-1.25", "-0.000000001", "-0", "-0.000",
                      "1969-12-31T23:59:59Z", "1969-12-31T23:59:59.999999999Z", "0001-01-01T00:00:00Z"])
    func negativeTimestampsStayInSearch(query: String) {
        #expect(TimestampCalculation.evaluate(query) == nil)
        #expect(Calculator.evaluate(query) == nil)
    }

    @Test(arguments: ["0.5", "0.000000001", "1710513000.123456789", "+1710513000.5",
                      "1710513000.0", "0.0", "253402300799.999999999"])
    func fractionalUnixSecondsStayInSearch(query: String) {
        #expect(TimestampCalculation.evaluate(query) == nil)
        #expect(Calculator.evaluate(query) == nil)
    }

    @Test func arithmeticStillSupportsNegativeNumbersAndFractions() {
        #expect(Calculator.evaluate("-2 + 1")?.answer == "-1")
        #expect(Calculator.evaluate("2 * -3")?.answer == "-6")
        #expect(Calculator.evaluate("0.1 + 0.2", locale: Locale(identifier: "en_US_POSIX"))?.answer == "0.3")
    }

    @Test func reverseConversionKeepsLocalTimeAsAHint() throws {
        let result = try #require(TimestampCalculation.evaluate("1710534600"))
        #expect(result.answer == "2024-03-15T20:30:00Z")
        #expect(result.localTimeHint(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
                == "2024-03-16 04:30:00 GMT+08:00")
    }

    @Test(arguments: [
        ("1710513000123", "2024-03-15T14:30:00.123Z"),
        ("1710513000000", "2024-03-15T14:30:00Z"),
        ("1710513000123 ms", "2024-03-15T14:30:00.123Z"),
        ("+1710513000123ms", "2024-03-15T14:30:00.123Z"),
        ("0 ms", "1970-01-01T00:00:00Z"),
        ("1ms", "1970-01-01T00:00:00.001Z"),
        ("999 ms", "1970-01-01T00:00:00.999Z"),
        ("1001ms", "1970-01-01T00:00:01.001Z"),
        ("253402300799999", "9999-12-31T23:59:59.999Z")
    ])
    func convertsWholeUnixMillisecondsToZulu(example: (String, String)) throws {
        let result = try #require(TimestampCalculation.evaluate(example.0))
        #expect(result.direction == .unixToZulu && result.unit == .milliseconds)
        #expect(result.answer == example.1)
        #expect(Calculator.evaluate(example.0)?.answer == example.1)
        #expect(TimestampCalculation.evaluate(result.answer, outputUnit: .milliseconds)?.answer == result.unixValue)
    }

    @Test(arguments: [
        ("1970-01-01T00:00:00Z", "0"),
        ("1970-01-01T00:00:00.000999999Z", "0"),
        ("1970-01-01T00:00:00.001Z", "1"),
        ("2024-03-15T14:30:00Z", "1710513000000"),
        ("2024-03-15T14:30:00.123456789Z", "1710513000123"),
        ("2024-03-15T14:30:00.999999999Z", "1710513000999"),
        ("9999-12-31T23:59:59.999999999Z", "253402300799999")
    ])
    func copiesWholeMillisecondsWithoutRounding(example: (String, String)) throws {
        let result = try #require(TimestampCalculation.evaluate(example.0, outputUnit: .milliseconds))
        #expect(result.answer == example.1)
        #expect(result.unit == .milliseconds)
        #expect(Calculator.evaluate(example.0, timestampUnit: .milliseconds)?.answer == example.1)
        #expect(TimestampCalculation.evaluate(example.0)?.answer == result.unixSeconds)
    }

    @Test func explicitUnitsResolveAmbiguousValuesWithoutChangingSeconds() throws {
        let seconds = try #require(TimestampCalculation.evaluate("253402300799"))
        #expect(seconds.unit == .seconds && seconds.answer == "9999-12-31T23:59:59Z")
        #expect(TimestampCalculation.evaluate("1710513000s")?.unit == .seconds)
        #expect(TimestampCalculation.evaluate("1710513000ms")?.unit == .milliseconds)
        #expect(TimestampCalculation.evaluate("1", outputUnit: .milliseconds)?.answer == "1970-01-01T00:00:01Z")
        let milliseconds = try #require(TimestampCalculation.evaluate("1710513000123"))
        #expect(milliseconds.localTimeHint(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
                == "2024-03-15 22:30:00.123 GMT+08:00")
    }

    @Test(arguments: ["-1ms", "-0 ms", "0.5 ms", "1710513000123.0ms", "1e3ms", "ms", "1m", "1 s ms"])
    func invalidMillisecondsStayInSearch(query: String) {
        #expect(TimestampCalculation.evaluate(query) == nil)
        #expect(Calculator.evaluate(query) == nil)
    }
}
