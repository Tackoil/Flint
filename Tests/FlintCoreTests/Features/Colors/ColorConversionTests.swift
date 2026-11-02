import Foundation
import Testing
@testable import FlintCore

struct ColorConversionTests {
    @Test(arguments: [
        ("#f63", "#ff6633"), ("#f638", "#ff663388"), (" #FF6363 ", "#ff6363"),
        ("#ff636380", "#ff636380"), ("rgb(255, 99, 99)", "#ff6363"),
        ("rgba(255, 99, 99, .5)", "#ff636380"), ("rgb(255 99 99 / 50%)", "#ff636380"),
        ("RGB(100% 0% 0%)", "#ff0000"), ("rgba(255 0 0)", "#ff0000"),
        ("hsl(0 100% 69%)", "#ff6161"), ("hsla(0, 100%, 50%, 50%)", "#ff000080"),
        ("hsl(.5turn 100% 50%)", "#00ffff"), ("hsl(200grad 100% 50%)", "#00ffff"),
        ("hsl(3.141592653589793rad 100% 50%)", "#00ffff"), ("hsl(-120 100% 50%)", "#0000ff"),
        ("hwb(0 0% 0% / 0)", "#ff000000"), ("hwb(270 80% 80%)", "#808080"),
        ("rgb(-10 300 0 / 200%)", "#00ff00"), ("rgb(1e2 0 0)", "#640000"),
        ("rgb(none 0 0 / none)", "#00000000")
    ])
    func parsesCSSColors(example: (String, String)) throws {
        let color = try #require(ColorConversion.evaluate(example.0, outputFormat: .hex))
        #expect(color.answer == example.1)
    }

    // Published CSS Color 4 red reference coordinates, including D50 Lab adaptation.
    @Test(arguments: [
        "lab(54.29054% 80.80492 69.89099)", "lch(54.29054% 106.83718 40.85767)",
        "oklab(62.795536% 0.224863 0.125846)", "oklch(62.795536% 0.257683 29.233885)",
        "lab(54.29054% 64.643936% 55.912792%)", "oklab(62.795536% 56.21575% 31.4615%)"
    ])
    func perceptualSpacesMatchReferenceRed(query: String) throws {
        let color = try #require(ColorConversion.evaluate(query))
        #expect(color.answer == "#ff0000")
        #expect(abs(color.rgb.x - 1) < 0.0001)
        #expect(abs(color.rgb.y) < 0.0001)
        #expect(abs(color.rgb.z) < 0.0001)
    }

    @Test(arguments: ["#ff636380", "#000", "#fff", "#808080", "#09f", "rgb(12.25 120.125 200 / .12345)"])
    func allFormatsRoundTripWithinDisplayPrecision(query: String) throws {
        let original = try #require(ColorConversion.evaluate(query))
        for format in ColorConversion.Format.allCases {
            var output = original
            output.format = format
            let decoded = try #require(ColorConversion.evaluate(output.answer))
            #expect(abs(decoded.rgb.x - original.rgb.x) < 0.0021, "\(output.answer)")
            #expect(abs(decoded.rgb.y - original.rgb.y) < 0.0021, "\(output.answer)")
            #expect(abs(decoded.rgb.z - original.rgb.z) < 0.0021, "\(output.answer)")
            #expect(abs(decoded.alpha - original.alpha) < 0.0021)
        }
    }

    @Test(arguments: [
        "", "Finder", "ff6363", "#12", "#12345", "#1234567", "#gggggg", "#ＦＦ0000",
        "rgb(255, 0 0)", "rgb(255, 0, 0,)", "rgb(255, 0, 0 / .5)", "rgb(1 2 3 4)",
        "rgb(1 2 3 /)", "rgb(1 2 3 / .5 / .5)", "rgb(1,,3)", "rgb(1% ,2, 3)",
        "rgb (1 2 3)", "rgb(1 2)", "rgb(NaN 0 0)", "rgb(1e999 0 0)", "rgb(1. 2 3)",
        "hsl(0, 50, 50)", "hwb(0, 0%, 0%)", "lab(50% 0)", "lch(50% 30 20%)",
        "oklab(50%, 0, 0)", "rgb(1 2 3) trailing", "rgb(calc(1) 2 3)", "hsl(1foo 50% 50%)"
    ])
    func malformedOrIncompleteColorsStayInSearch(query: String) {
        #expect(ColorConversion.evaluate(query) == nil)
    }

    @Test func boundsInputAndKeepsNormalCalculatorBehavior() {
        #expect(ColorConversion.evaluate("rgb(" + String(repeating: "0 ", count: 300) + ")") == nil)
        #expect(Calculator.evaluate("2+3")?.answer == "5")
        #expect(Calculator.evaluate("1710513000")?.answer == "2024-03-15T14:30:00Z")
        #expect(Calculator.evaluate("rgb(255 99 99)")?.answer == "#ff6363")
        #expect(Calculator.evaluate("#ff6363")?.answer == "rgb(255 99 99)")
        #expect(Calculator.evaluate("#ff6363", colorFormat: .hsl)?.answer == "hsl(0 100% 69.41%)")
    }

    @Test func formatSwitchingWrapsAndKeepsOriginalColor() throws {
        #expect(ColorConversion.Format.hex.shifted(by: -1) == .oklch)
        #expect(ColorConversion.Format.oklch.shifted(by: 1) == .hex)
        var color = try #require(ColorConversion.evaluate("rgb(255 0 0 / .5)"))
        color.format = .rgb
        #expect(color.answer == "rgb(255 0 0 / 0.5)")
        color.format = .hex
        #expect(color.answer == "#ff000080")
        color.format = .rgb
        #expect(color.answer == "rgb(255 0 0 / 0.5)")
    }

    @Test func outOfGamutValuesSurvivePerceptualConversions() throws {
        var color = try #require(ColorConversion.evaluate("oklch(70% .4 30)"))
        #expect(color.isOutsideSRGB)
        #expect(color.previewRGB.x == 1 && color.previewRGB.y == 0)
        color.format = .oklch
        #expect(color.answer == "oklch(70% 0.4 30)")
        color.format = .lab
        let restored = try #require(ColorConversion.evaluate(color.answer, outputFormat: .oklch))
        #expect(abs(restored.rgb.x - color.rgb.x) < 0.0001)
        #expect(abs(restored.rgb.y - color.rgb.y) < 0.0001)
        #expect(abs(restored.rgb.z - color.rgb.z) < 0.0001)
    }
}
