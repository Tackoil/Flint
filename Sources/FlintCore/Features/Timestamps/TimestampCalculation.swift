import Foundation

struct TimestampCalculation: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case zuluToUnix, unixToZulu }
    enum Unit: Equatable, Sendable {
        case seconds, milliseconds

        var scale: Int64 { self == .milliseconds ? 1_000 : 1 }
        var title: String { self == .milliseconds ? "Unix milliseconds" : "Unix seconds" }
    }

    let expression: String
    let direction: Direction
    let unit: Unit
    private let date: Date
    private let fraction: String

    var answer: String {
        direction == .unixToZulu ? zuluTimestamp : unixValue
    }

    var unixSeconds: String {
        String(Int64(date.timeIntervalSince1970))
    }

    var unixMilliseconds: String {
        let milliseconds = Int64((fraction + "000").prefix(3)) ?? 0
        return String(Int64(date.timeIntervalSince1970) * 1_000 + milliseconds)
    }

    var unixValue: String { unit == .milliseconds ? unixMilliseconds : unixSeconds }

    var zuluTimestamp: String {
        let formatter = Self.formatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let timestamp = formatter.string(from: date)
        guard !fraction.isEmpty else { return timestamp }
        return String(timestamp.dropLast()) + ".\(fraction)Z"
    }

    func localTimeHint(timeZone: TimeZone = .current) -> String {
        let formatter = Self.formatter(timeZone: timeZone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let local = formatter.string(from: date)
        formatter.dateFormat = "ZZZZ"
        let suffix = fraction.isEmpty ? "" : ".\(fraction)"
        return "\(local)\(suffix) \(formatter.string(from: date))"
    }

    static func evaluate(_ query: String, outputUnit: Unit = .seconds) -> TimestampCalculation? {
        let expression = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expression.utf8.count <= 30 else { return nil }
        return evaluateZulu(expression, unit: outputUnit) ?? evaluateUnix(expression)
    }

    private static func evaluateZulu(_ expression: String, unit: Unit) -> TimestampCalculation? {
        let pattern = #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-2][0-9]:[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,9})?Z\z"#
        guard expression.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let wholeSeconds = String(expression.prefix(19)) + "Z"
        let formatter = Self.formatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        // Foundation can normalize invalid calendar dates; require an exact round trip.
        guard let date = formatter.date(from: wholeSeconds),
              date.timeIntervalSince1970 >= 0,
              formatter.string(from: date) == wholeSeconds else { return nil }
        let fraction = expression.dropFirst(19).dropLast().dropFirst()
        return TimestampCalculation(expression: expression, direction: .zuluToUnix, unit: unit,
                                    date: date, fraction: String(fraction))
    }

    private static func evaluateUnix(_ expression: String) -> TimestampCalculation? {
        let (number, explicitUnit) = splitUnixUnit(expression)
        let pattern = #"\A\+?[0-9]+\z"#
        guard number.range(of: pattern, options: .regularExpression) != nil,
              let value = Int64(number), value >= 0 else { return nil }
        let unit = explicitUnit ?? (value < 253_402_300_800 ? .seconds : .milliseconds)
        guard value < 253_402_300_800 * unit.scale else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(value / unit.scale))
        let remainder = value % unit.scale
        let fraction = remainder == 0 ? "" : String(format: "%03lld", remainder)
        return TimestampCalculation(expression: expression, direction: .unixToZulu, unit: unit,
                                    date: date, fraction: fraction)
    }

    private static func splitUnixUnit(_ expression: String) -> (String, Unit?) {
        for (suffix, unit) in [("ms", Unit.milliseconds), ("s", Unit.seconds)] {
            if expression.hasSuffix(suffix) {
                return (String(expression.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces), unit)
            }
        }
        return (expression, nil)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.isLenient = false
        return formatter
    }
}
