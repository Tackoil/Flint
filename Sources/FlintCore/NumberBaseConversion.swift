import Foundation

struct NumberBaseConversion: Equatable, Sendable {
    enum Format: CaseIterable, Sendable {
        case decimal, hex, binary

        var title: String {
            switch self {
            case .decimal: return "DEC"
            case .hex: return "HEX"
            case .binary: return "BIN"
            }
        }

        var radix: Int {
            switch self {
            case .decimal: return 10
            case .hex: return 16
            case .binary: return 2
            }
        }

        var prefix: String {
            switch self {
            case .decimal: return "0d"
            case .hex: return "0x"
            case .binary: return "0b"
            }
        }

        func shifted(by offset: Int) -> Self {
            let formats = Self.allCases
            let index = formats.firstIndex(of: self)!
            return formats[((index + offset) % formats.count + formats.count) % formats.count]
        }
    }

    let expression: String
    let magnitude: UInt64
    let isNegative: Bool
    var format: Format

    var answer: String { value(in: format) }

    static func hasExplicitPrefix(_ query: String) -> Bool {
        let literal = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unsigned = literal.hasPrefix("+") || literal.hasPrefix("-") ? String(literal.dropFirst()) : literal
        return Format.allCases.contains { unsigned.hasPrefix($0.prefix) }
    }

    func value(in format: Format, grouped: Bool = false) -> String {
        let digits = String(magnitude, radix: format.radix, uppercase: true)
        let sign = isNegative ? "-" : ""
        let prefix = format == .decimal ? "" : format.prefix
        guard grouped, format == .binary else { return sign + prefix + digits }
        let groups = digits.enumerated().map { index, digit in
            let separator = index > 0 && (digits.count - index).isMultiple(of: 4) ? " " : ""
            return separator + String(digit)
        }.joined()
        return sign + prefix + groups
    }

    static func evaluate(_ query: String, outputFormat: Format? = nil) -> Self? {
        let expression = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expression.utf8.count <= 128 else { return nil }
        let literal = expression.lowercased()
        let negative = literal.hasPrefix("-")
        let unsigned = literal.hasPrefix("+") || negative ? String(literal.dropFirst()) : literal
        guard let source = Format.allCases.first(where: { unsigned.hasPrefix($0.prefix) }) else { return nil }
        let digits = String(unsigned.dropFirst(2))
        let allowed = String("0123456789abcdef".prefix(source.radix))
        guard !digits.isEmpty, digits.allSatisfy({ allowed.contains($0) }),
              let magnitude = UInt64(digits, radix: source.radix) else { return nil }
        return Self(expression: expression, magnitude: magnitude, isNegative: negative && magnitude != 0,
                    format: outputFormat ?? (source == .decimal ? .hex : .decimal))
    }
}
