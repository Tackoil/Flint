import Foundation

enum NumericOperator: Hashable {
    case add, subtract, multiply, divide, power

    var precedence: Int {
        switch self {
        case .add, .subtract: return 10
        case .multiply, .divide: return 20
        case .power: return 30
        }
    }

    func apply(_ left: Decimal, _ right: Decimal) throws -> Decimal {
        if self == .power { return try power(left, right) }
        if self == .divide && right == 0 { throw NumericCalculationError.divisionByZero }
        var lhs = left
        var rhs = right
        var result = Decimal()
        typealias Operation = (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>,
                              UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError
        let operations: [Self: Operation] = [
            .add: NSDecimalAdd, .subtract: NSDecimalSubtract,
            .multiply: NSDecimalMultiply, .divide: NSDecimalDivide
        ]
        guard let operation = operations[self] else { throw NumericCalculationError.invalid }
        let status = operation(&result, &lhs, &rhs, .plain)
        return try checked(result, status: status)
    }

    private func power(_ base: Decimal, _ exponent: Decimal) throws -> Decimal {
        if base == 0 && exponent < 0 { throw NumericCalculationError.divisionByZero }
        var rounded = Decimal()
        var exponentCopy = exponent
        NSDecimalRound(&rounded, &exponentCopy, 0, .plain)
        if rounded == exponent && abs(exponent) <= 1_024 {
            var value = base
            var result = Decimal()
            let integer = NSDecimalNumber(decimal: abs(exponent)).intValue
            let status = NSDecimalPower(&result, &value, integer, .plain)
            let magnitude = try checked(result, status: status)
            return exponent < 0 ? try NumericOperator.divide.apply(1, magnitude) : magnitude
        }
        let value = Foundation.pow(NSDecimalNumber(decimal: base).doubleValue,
                                   NSDecimalNumber(decimal: exponent).doubleValue)
        guard value.isFinite, let result = Decimal(string: String(value)), !result.isNaN,
              value != 0 || base == 0 else { throw NumericCalculationError.outOfRange }
        return result
    }

    private func checked(_ value: Decimal, status: Decimal.CalculationError) throws -> Decimal {
        guard status == .noError || status == .lossOfPrecision, !value.isNaN else {
            throw NumericCalculationError.outOfRange
        }
        return value
    }
}
