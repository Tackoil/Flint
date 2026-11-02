import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct QRCode {
    static let maximumByteCount = 2_000
    let image: CGImage
    let pngData: Data

    enum GenerationError: LocalizedError {
        case empty, tooLong, unavailable

        var errorDescription: String? {
            switch self {
            case .empty: return "Type or paste text or a URL to generate a QR code."
            case .tooLong: return "This text is too long. Use at most 2,000 UTF-8 bytes."
            case .unavailable: return "Couldn’t generate a QR code. Try shorter text."
            }
        }
    }

    init(text: String) throws {
        guard !text.isEmpty else { throw GenerationError.empty }
        let data = Data(text.utf8)
        guard data.count <= Self.maximumByteCount else { throw GenerationError.tooLong }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw GenerationError.unavailable }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let code = CIContext().createCGImage(output, from: output.extent) else {
            throw GenerationError.unavailable
        }
        image = try Self.render(code)
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else {
            throw GenerationError.unavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationError.unavailable }
        pngData = buffer as Data
    }

    private static func render(_ code: CGImage) throws -> CGImage {
        // Four white modules on every side keep the code scannable on any surface.
        let modules = code.width + 8
        let scale = max(1, 1_024 / modules)
        let size = modules * scale
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw GenerationError.unavailable
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .none
        context.draw(code, in: CGRect(x: 4 * scale, y: 4 * scale,
                                     width: code.width * scale, height: code.height * scale))
        guard let image = context.makeImage() else { throw GenerationError.unavailable }
        return image
    }
}
