import Foundation

// CSS Color 4 conversion matrices and D50/D65 Bradford adaptation:
// https://www.w3.org/TR/css-color-4/#color-conversion-code
// Keep extended sRGB internally so Lab/OKLab conversions retain out-of-gamut colors.
enum ColorSpaceMath {
    typealias Vector = SIMD3<Double>

    static func map(_ v: Vector, _ transform: (Double) -> Double) -> Vector {
        Vector(transform(v.x), transform(v.y), transform(v.z))
    }

    static func matrix(_ rows: [Vector], _ v: Vector) -> Vector {
        func dot(_ row: Vector) -> Double { let p = row * v; return p.x + p.y + p.z }
        return Vector(dot(rows[0]), dot(rows[1]), dot(rows[2]))
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    static func clipped(_ rgb: Vector) -> Vector { map(rgb, clamp) }
    static func hue(_ value: Double) -> Double { (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

    static func linear(_ value: Double) -> Double {
        let magnitude = abs(value)
        return magnitude <= 0.04045 ? value / 12.92 : copysign(pow((magnitude + 0.055) / 1.055, 2.4), value)
    }

    static func gamma(_ value: Double) -> Double {
        let magnitude = abs(value)
        return magnitude <= 0.0031308 ? 12.92 * value : copysign(1.055 * pow(magnitude, 1 / 2.4) - 0.055, value)
    }

    static func rgbToXYZ(_ rgb: Vector) -> Vector {
        matrix([Vector(0.4123907992659595, 0.357584339383878, 0.1804807884018343),
                Vector(0.2126390058715104, 0.715168678767756, 0.0721923153607337),
                Vector(0.0193308187155919, 0.119194779794626, 0.9505321522496606)], map(rgb, linear))
    }

    static func xyzToRGB(_ xyz: Vector) -> Vector {
        map(matrix([Vector(3.2409699419045226, -1.537383177570094, -0.4986107602930034),
                    Vector(-0.9692436362808796, 1.8759675015077202, 0.0415550574071756),
                    Vector(0.0556300796969937, -0.2039769588889765, 1.0569715142428786)], xyz), gamma)
    }

    static func rgbToLab(_ rgb: Vector) -> Vector {
        let xyz = matrix([Vector(1.0479297925449969, 0.0229468706016097, -0.0501922662892052),
                          Vector(0.029627808770056, 0.9904344267538799, -0.0170737990634188),
                          Vector(-0.0092430406462045, 0.0150551914902982, 0.7518742814281371)], rgbToXYZ(rgb))
        let f = map(xyz / Vector(0.3457 / 0.3585, 1, 0.2958 / 0.3585)) {
            $0 > 216.0 / 24389 ? cbrt($0) : (24389.0 / 27 * $0 + 16) / 116
        }
        return Vector(116 * f.y - 16, 500 * (f.x - f.y), 200 * (f.y - f.z))
    }

    static func labToRGB(_ lab: Vector) -> Vector {
        if lab.x <= 0 { return .zero }
        if lab.x >= 100 { return Vector(repeating: 1) }
        let fy = (lab.x + 16) / 116
        let f = Vector(fy + lab.y / 500, fy, fy - lab.z / 200)
        let xyz = map(f) { pow($0, 3) > 216.0 / 24389 ? pow($0, 3) : (116 * $0 - 16) / (24389.0 / 27) }
            * Vector(0.3457 / 0.3585, 1, 0.2958 / 0.3585)
        return xyzToRGB(matrix([Vector(0.955473421488075, -0.0230984549487647, 0.0632592432005707),
                                Vector(-0.0283697093338637, 1.0099953980813041, 0.0210414411919173),
                                Vector(0.012314014864482, -0.020507649298899, 1.330365926242124)], xyz))
    }

    static func rgbToOKLab(_ rgb: Vector) -> Vector {
        let lms = matrix([Vector(0.819022437996703, 0.3619062600528904, -0.1288737815209879),
                          Vector(0.0329836539323885, 0.9292868615863434, 0.0361446663506424),
                          Vector(0.0481771893596242, 0.2642395317527308, 0.6335478284694309)], rgbToXYZ(rgb))
        return matrix([Vector(0.210454268309314, 0.7936177747023054, -0.0040720430116193),
                       Vector(1.9779985324311684, -2.42859224204858, 0.450593709617411),
                       Vector(0.0259040424655478, 0.7827717124575296, -0.8086757549230774)], map(lms, cbrt))
    }

    static func oklabToRGB(_ lab: Vector) -> Vector {
        if lab.x <= 0 { return .zero }
        if lab.x >= 1 { return Vector(repeating: 1) }
        let lms = matrix([Vector(1, 0.3963377773761749, 0.2158037573099136),
                          Vector(1, -0.1055613458156586, -0.0638541728258133),
                          Vector(1, -0.0894841775298119, -1.2914855480194092)], lab)
        return xyzToRGB(matrix([Vector(1.2268798758459243, -0.5578149944602171, 0.2813910456659647),
                                Vector(-0.0405757452148008, 1.112286803280317, -0.0717110580655164),
                                Vector(-0.0763729366746601, -0.4214933324022432, 1.5869240198367816)], map(lms) { $0 * $0 * $0 }))
    }

    static func polar(_ lab: Vector) -> Vector {
        let chroma = hypot(lab.y, lab.z)
        return Vector(lab.x, chroma, chroma < 0.000004 ? 0 : hue(atan2(lab.z, lab.y) * 180 / .pi))
    }

    static func rectangular(_ lch: Vector) -> Vector {
        Vector(lch.x, lch.y * cos(lch.z * .pi / 180), lch.y * sin(lch.z * .pi / 180))
    }

    static func hslToRGB(_ hsl: Vector) -> Vector {
        let h = hue(hsl.x) / 30
        let a = hsl.y * min(hsl.z, 1 - hsl.z)
        func channel(_ n: Double) -> Double {
            let k = (n + h).truncatingRemainder(dividingBy: 12)
            return hsl.z - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return Vector(channel(0), channel(8), channel(4))
    }

    static func rgbToHSL(_ rgb: Vector) -> Vector {
        let high = max(rgb.x, rgb.y, rgb.z)
        let low = min(rgb.x, rgb.y, rgb.z)
        let delta = high - low
        let lightness = (high + low) / 2
        guard delta > 1e-10 else { return Vector(0, 0, lightness) }
        let sectors = Vector((rgb.y - rgb.z) / delta, (rgb.z - rgb.x) / delta + 2, (rgb.x - rgb.y) / delta + 4)
        let sector = high == rgb.x ? sectors.x : (high == rgb.y ? sectors.y : sectors.z)
        return Vector(hue(sector * 60), delta / (1 - abs(2 * lightness - 1)), lightness)
    }

    static func hwbToRGB(_ hwb: Vector) -> Vector {
        let sum = hwb.y + hwb.z
        if sum >= 1 { return Vector(repeating: hwb.y / sum) }
        return hslToRGB(Vector(hwb.x, 1, 0.5)) * (1 - sum) + Vector(repeating: hwb.y)
    }
}
