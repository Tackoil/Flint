import Foundation

enum ColorParser {
    typealias Vector = SIMD3<Double>
    private static let names = ["rgb": "rgb", "rgba": "rgb", "hsl": "hsl", "hsla": "hsl",
                                "hwb": "hwb", "lab": "lab", "lch": "lch", "oklab": "oklab", "oklch": "oklch"]

    static func parse(_ input: String) -> (Vector, Double)? {
        if input.hasPrefix("#") { return hex(String(input.dropFirst())) }
        guard let open = input.firstIndex(of: "("), input.hasSuffix(")"),
              let name = names[String(input[..<open])] else { return nil }
        let body = String(input[input.index(after: open)..<input.index(before: input.endIndex)])
        guard let tokens = components(body, name: name),
              let alpha = scalar(tokens.count == 4 ? tokens[3] : "1", percentScale: 1),
              let rgb = channels(Array(tokens.prefix(3)), name: name) else { return nil }
        return (rgb, ColorSpaceMath.clamp(alpha))
    }

    private static func hex(_ input: String) -> (Vector, Double)? {
        guard [3, 4, 6, 8].contains(input.count), input.allSatisfy(\.isHexDigit), input.isASCII else { return nil }
        let expanded = input.count < 5 ? input.map { String(repeating: String($0), count: 2) }.joined() : input
        let bytes = Array(expanded.utf8)
        let values = stride(from: 0, to: bytes.count, by: 2).map { index in
            Double(UInt8(String(decoding: bytes[index..<index + 2], as: UTF8.self), radix: 16)!) / 255
        }
        return (Vector(values[0], values[1], values[2]), values.count == 4 ? values[3] : 1)
    }

    private static func components(_ body: String, name: String) -> [String]? {
        if body.contains(",") { return legacyComponents(body, name: name) }
        let parts = body.components(separatedBy: "/")
        guard parts.count <= 2 else { return nil }
        let channels = parts[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard channels.count == 3 else { return nil }
        guard parts.count == 2 else { return channels }
        let alpha = parts[1].split(whereSeparator: \.isWhitespace).map(String.init)
        return alpha.count == 1 ? channels + alpha : nil
    }

    private static func legacyComponents(_ body: String, name: String) -> [String]? {
        guard ["rgb", "hsl"].contains(name), !body.contains("/"), !body.contains("none") else { return nil }
        let tokens = body.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard [3, 4].contains(tokens.count), !tokens.contains("") else { return nil }
        if name == "rgb" {
            let percentages = tokens.prefix(3).filter { $0.hasSuffix("%") }.count
            guard percentages == 0 || percentages == 3 else { return nil }
        } else {
            guard tokens[1].hasSuffix("%"), tokens[2].hasSuffix("%") else { return nil }
        }
        return tokens
    }

    private static func channels(_ t: [String], name: String) -> Vector? {
        switch name {
        case "rgb": return rgbChannels(t)
        case "hsl", "hwb": return hueChannels(t, name: name)
        default: return labChannels(t, name: name)
        }
    }

    private static func rgbChannels(_ t: [String]) -> Vector? {
        guard let v = vector(t, scales: Vector(repeating: 255)) else { return nil }
        return ColorSpaceMath.clipped(v / 255)
    }

    private static func hueChannels(_ t: [String], name: String) -> Vector? {
        guard let hue = angle(t[0]), let s = scalar(t[1], percentScale: 100),
              let l = scalar(t[2], percentScale: 100) else { return nil }
        let v = Vector(hue, ColorSpaceMath.clamp(s / 100), ColorSpaceMath.clamp(l / 100))
        return name == "hsl" ? ColorSpaceMath.hslToRGB(v) : ColorSpaceMath.hwbToRGB(v)
    }

    private static func labChannels(_ t: [String], name: String) -> Vector? {
        let isOK = name.hasPrefix("ok")
        let isPolar = name.hasSuffix("lch")
        let scales = Vector(isOK ? 1 : 100, isOK ? 0.4 : (isPolar ? 150 : 125), isOK ? 0.4 : 125)
        guard let lightness = scalar(t[0], percentScale: scales.x),
              let second = scalar(t[1], percentScale: scales.y),
              let third = isPolar ? angle(t[2]) : scalar(t[2], percentScale: scales.z) else { return nil }
        var v = Vector(ColorSpaceMath.clamp(lightness / scales.x) * scales.x, second, third)
        if isPolar { v.y = max(0, v.y); v = ColorSpaceMath.rectangular(v) }
        return isOK ? ColorSpaceMath.oklabToRGB(v) : ColorSpaceMath.labToRGB(v)
    }

    private static func vector(_ tokens: [String], scales: Vector) -> Vector? {
        guard let x = scalar(tokens[0], percentScale: scales.x),
              let y = scalar(tokens[1], percentScale: scales.y),
              let z = scalar(tokens[2], percentScale: scales.z) else { return nil }
        return Vector(x, y, z)
    }

    private static func scalar(_ token: String, percentScale: Double) -> Double? {
        if token == "none" { return 0 }
        let percent = token.hasSuffix("%")
        let text = percent ? String(token.dropLast()) : token
        guard let value = number(text) else { return nil }
        return percent ? value / 100 * percentScale : value
    }

    private static func angle(_ token: String) -> Double? {
        if token == "none" { return 0 }
        for (unit, scale) in [("deg", 1.0), ("grad", 0.9), ("rad", 180 / Double.pi), ("turn", 360)] {
            if token.hasSuffix(unit) { return number(String(token.dropLast(unit.count))).map { ColorSpaceMath.hue($0 * scale) } }
        }
        return number(token).map(ColorSpaceMath.hue)
    }

    private static func number(_ text: String) -> Double? {
        let pattern = #"\A[+-]?(?:[0-9]*\.[0-9]+|[0-9]+)(?:e[+-]?[0-9]+)?\z"#
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let value = Double(text), value.isFinite, abs(value) <= 1e12 else { return nil }
        return value
    }
}

private extension String {
    var isASCII: Bool { utf8.allSatisfy { $0 < 128 } }
}
