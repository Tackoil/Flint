import Foundation

struct ColorConversion: Equatable, Sendable {
    enum Format: String, CaseIterable, Sendable {
        case hex, rgb, hsl, hwb, lab, lch, oklab, oklch

        var title: String { rawValue.uppercased() }
        var usesSRGB: Bool { [.hex, .rgb, .hsl, .hwb].contains(self) }

        func shifted(by offset: Int) -> Format {
            let formats = Self.allCases
            let index = formats.firstIndex(of: self)!
            return formats[((index + offset) % formats.count + formats.count) % formats.count]
        }
    }

    let expression: String
    let rgb: SIMD3<Double>
    let alpha: Double
    var format: Format

    var previewRGB: SIMD3<Double> { ColorSpaceMath.clipped(rgb) }
    var isOutsideSRGB: Bool {
        min(rgb.x, rgb.y, rgb.z) < -0.00001 || max(rgb.x, rgb.y, rgb.z) > 1.00001
    }

    var answer: String {
        if format == .hex { return hexAnswer }
        let components = outputComponents
        let opacity = alpha < 1 ? " / \(Self.number(alpha, places: 5))" : ""
        return "\(format.rawValue)(\(components.joined(separator: " "))\(opacity))"
    }

    private var hexAnswer: String {
        var channels = [previewRGB.x, previewRGB.y, previewRGB.z]
        if alpha < 1 { channels.append(alpha) }
        return "#" + channels.map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
    }

    private var outputComponents: [String] {
        let color = previewRGB
        switch format {
        case .hex: return []
        case .rgb: return [color.x, color.y, color.z].map { Self.number($0 * 255, places: 3) }
        case .hsl:
            let hsl = ColorSpaceMath.rgbToHSL(color)
            return [Self.number(hsl.x), Self.number(hsl.y * 100) + "%", Self.number(hsl.z * 100) + "%"]
        case .hwb:
            return [Self.number(ColorSpaceMath.rgbToHSL(color).x),
                    Self.number(min(color.x, color.y, color.z) * 100) + "%",
                    Self.number((1 - max(color.x, color.y, color.z)) * 100) + "%"]
        case .lab: return labComponents(ColorSpaceMath.rgbToLab(rgb), isOK: false)
        case .lch: return labComponents(ColorSpaceMath.polar(ColorSpaceMath.rgbToLab(rgb)), isOK: false)
        case .oklab: return labComponents(ColorSpaceMath.rgbToOKLab(rgb), isOK: true)
        case .oklch: return labComponents(ColorSpaceMath.polar(ColorSpaceMath.rgbToOKLab(rgb)), isOK: true)
        }
    }

    private func labComponents(_ v: SIMD3<Double>, isOK: Bool) -> [String] {
        let places = isOK ? 5 : 3
        return [Self.number(v.x * (isOK ? 100 : 1), places: 3) + "%",
                Self.number(v.y, places: places), Self.number(v.z, places: places)]
    }

    private static func number(_ value: Double, places: Int = 2) -> String {
        let rounded = (value * pow(10, Double(places))).rounded() / pow(10, Double(places))
        if rounded == 0 { return "0" }
        let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, rounded)
        return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    static func evaluate(_ query: String, outputFormat: Format? = nil) -> ColorConversion? {
        let expression = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expression.utf8.count <= 512, let parsed = ColorParser.parse(expression.lowercased()) else { return nil }
        let rgb = parsed.0
        guard [rgb.x, rgb.y, rgb.z, parsed.1].allSatisfy(\.isFinite) else { return nil }
        return ColorConversion(expression: expression, rgb: rgb, alpha: parsed.1,
                               format: outputFormat ?? (expression.hasPrefix("#") ? .rgb : .hex))
    }
}
