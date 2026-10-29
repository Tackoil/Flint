import Foundation

enum NumericToken: Equatable {
    case number(Decimal), operation(NumericOperator), open, close, percent, end
}

struct NumericExpressionParser {
    private let tokens: [NumericToken]
    private var position = 0
    private(set) var hasOperation = false
    private var current: NumericToken { tokens[position] }

    init(_ expression: String) throws {
        var lexer = NumericExpressionLexer(expression)
        tokens = try lexer.tokenize()
    }

    mutating func evaluate() throws -> Decimal {
        let value = try expression(minimumPrecedence: 0, depth: 0)
        guard current == .end else { throw NumericCalculationError.invalid }
        return value == 0 ? 0 : value
    }

    private mutating func expression(minimumPrecedence: Int, depth: Int) throws -> Decimal {
        guard depth < 64 else { throw NumericCalculationError.tooLong }
        var value = try operand(depth: depth)
        while case .operation(let operation) = current, operation.precedence >= minimumPrecedence {
            position += 1
            let nextPrecedence = operation.precedence + (operation == .power ? 0 : 1)
            let right = try expression(minimumPrecedence: nextPrecedence, depth: depth + 1)
            value = try operation.apply(value, right)
            hasOperation = true
        }
        return value
    }

    private mutating func operand(depth: Int) throws -> Decimal {
        if case .number(let number) = current {
            position += 1
            return try percentages(of: number)
        }
        if current == .operation(.add) || current == .operation(.subtract) {
            return try signedOperand(depth: depth)
        }
        guard current != .end else { throw NumericCalculationError.incomplete }
        guard current == .open else { throw NumericCalculationError.invalid }
        position += 1
        let value = try expression(minimumPrecedence: 0, depth: depth + 1)
        guard current != .end else { throw NumericCalculationError.incomplete }
        guard current == .close else { throw NumericCalculationError.invalid }
        position += 1
        return try percentages(of: value)
    }

    private mutating func signedOperand(depth: Int) throws -> Decimal {
        let isNegative = current == .operation(.subtract)
        position += 1
        let magnitude = try expression(minimumPrecedence: NumericOperator.power.precedence, depth: depth + 1)
        return isNegative ? -magnitude : magnitude
    }

    private mutating func percentages(of value: Decimal) throws -> Decimal {
        var result = value
        while current == .percent {
            result = try NumericOperator.divide.apply(result, 100)
            hasOperation = true
            position += 1
        }
        return result
    }
}

private struct NumericExpressionLexer {
    private let characters: [Character]
    private var position = 0
    private var current: Character? { position < characters.count ? characters[position] : nil }
    private let symbols: [Character: NumericToken] = [
        "+": .operation(.add), "-": .operation(.subtract), "−": .operation(.subtract),
        "*": .operation(.multiply), "×": .operation(.multiply), "x": .operation(.multiply), "X": .operation(.multiply),
        "/": .operation(.divide), "÷": .operation(.divide), "^": .operation(.power),
        "(": .open, ")": .close, "%": .percent
    ]

    init(_ expression: String) { characters = Array(expression) }

    mutating func tokenize() throws -> [NumericToken] {
        var tokens: [NumericToken] = []
        while let character = current {
            if character.isWhitespace {
                position += 1
            } else if let token = symbols[character] {
                tokens.append(token)
                position += 1
            } else {
                tokens.append(.number(try number()))
            }
        }
        return tokens + [.end]
    }

    private mutating func number() throws -> Decimal {
        let start = position
        consumeCharacters(in: "0123456789.")
        guard position > start else { throw NumericCalculationError.invalid }
        if current == "e" || current == "E" {
            position += 1
            if current == "+" || current == "-" { position += 1 }
            let exponentStart = position
            consumeCharacters(in: "0123456789")
            guard position > exponentStart else { throw NumericCalculationError.incomplete }
        }
        let literal = String(characters[start..<position])
        guard literal.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                            options: .regularExpression) != nil else { throw NumericCalculationError.invalid }
        guard let value = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else {
            throw NumericCalculationError.outOfRange
        }
        return value
    }

    private mutating func consumeCharacters(in allowed: String) {
        while let character = current, allowed.contains(character) { position += 1 }
    }
}
