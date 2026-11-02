import Foundation
import Testing
@testable import FlintCore

struct NumberBaseConversionTests {
    @Test(arguments: [
        ("0xff", "255", "0xFF", "0b11111111"),
        ("0b101010", "42", "0x2A", "0b101010"),
        ("0d255", "255", "0xFF", "0b11111111"),
        ("-0xff", "-255", "-0xFF", "-0b11111111"),
        ("+0B001010", "10", "0xA", "0b1010"),
        (" \n0XfF \n", "255", "0xFF", "0b11111111"),
        ("-0d0", "0", "0x0", "0b0"),
        ("0d00042", "42", "0x2A", "0b101010"),
        ("-0b101010", "-42", "-0x2A", "-0b101010")
    ])
    func convertsExactIntegers(example: (String, String, String, String)) throws {
        let number = try #require(NumberBaseConversion.evaluate(example.0))
        #expect(number.value(in: .decimal) == example.1)
        #expect(number.value(in: .hex) == example.2)
        #expect(number.value(in: .binary) == example.3)
    }

    @Test func defaultsAndSelection() throws {
        #expect(NumberBaseConversion.evaluate("0xff")?.format == .decimal)
        #expect(NumberBaseConversion.evaluate("0b11")?.format == .decimal)
        #expect(NumberBaseConversion.evaluate("0d255")?.format == .hex)
        var number = try #require(NumberBaseConversion.evaluate("0xff", outputFormat: .binary))
        #expect(number.answer == "0b11111111")
        number.format = number.format.shifted(by: 1)
        #expect(number.answer == "255")
        #expect(number.format.shifted(by: -1) == .binary)
        #expect(number.format.shifted(by: 3) == .decimal)
    }

    @Test func binaryGroupingDoesNotAffectCopyValue() throws {
        let number = try #require(NumberBaseConversion.evaluate("-0x12345", outputFormat: .binary))
        #expect(number.value(in: .binary, grouped: true) == "-0b1 0010 0011 0100 0101")
        #expect(number.answer == "-0b10010001101000101")
        #expect(NumberBaseConversion.evaluate("0b0")?.value(in: .binary, grouped: true) == "0b0")
    }

    @Test(arguments: [UInt64(0), 1, 15, 16, 255, 256, 9_007_199_254_740_993, UInt64(Int64.max),
                      UInt64(Int64.max) + 1, UInt64.max])
    func fullWidthValuesRoundTrip(magnitude: UInt64) throws {
        for sign in ["", "-"] {
            let original = try #require(NumberBaseConversion.evaluate(sign + "0d" + String(magnitude)))
            for format in NumberBaseConversion.Format.allCases {
                let prefix = format == .decimal ? "0d" : ""
                let value = original.value(in: format)
                let literal = value.hasPrefix("-") ? "-" + prefix + value.dropFirst() : prefix + value
                let restored = try #require(NumberBaseConversion.evaluate(literal))
                #expect(restored.magnitude == magnitude)
                #expect(restored.isNegative == (sign == "-" && magnitude != 0))
            }
        }
    }

    @Test(arguments: ["", "0x", "-0b", "+0d", "0xGG", "0b102", "0d1.5", "0d1e3", "0x1+2",
                      "0x-ff", "--0xff", "0x1 2", "0x1_2", "0d１２", "0xＦＦ", "0d١٢", "0x+ff",
                      "0xff extra", "0o77", "0d18446744073709551616", "0x10000000000000000",
                      "-0d18446744073709551616", "0b10000000000000000000000000000000000000000000000000000000000000000"])
    func invalidInputStaysInSearch(query: String) {
        #expect(NumberBaseConversion.evaluate(query) == nil)
        #expect(Calculator.evaluate(query) == nil)
    }

    @Test func boundsInputAndPreservesOtherTools() {
        #expect(NumberBaseConversion.evaluate("0x" + String(repeating: "0", count: 127)) == nil)
        guard case .timestamp = Calculator.evaluate("255"),
              case .color = Calculator.evaluate("#ff6600"),
              case .numeric = Calculator.evaluate("2+3"),
              case .numberBase = Calculator.evaluate("0d255") else {
            Issue.record("Number conversion must coexist with timestamps, colors, and arithmetic")
            return
        }
        #expect(Calculator.evaluate("0xff", numberBaseFormat: .hex)?.answer == "0xFF")
    }
}
