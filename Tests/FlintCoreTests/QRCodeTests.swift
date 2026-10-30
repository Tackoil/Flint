import Foundation
import ImageIO
import Testing
import Vision
@testable import FlintCore

struct QRCodeTests {
    @Test(arguments: ["https://example.com/search?q=hello&lang=en", "Hello, Flint!", "你好，世界 🌏", "  first line\nsecond line\r\n  ", "2+2"])
    func exportedPNGRoundTrips(text: String) throws {
        let code = try QRCode(text: text)
        let source = try #require(CGImageSourceCreateWithData(code.pngData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == image.height)
        #expect(image.width <= 1_024 && image.width >= 800)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        #expect(request.results?.first?.payloadStringValue == text)
    }

    @Test func limitsUseUTF8Bytes() throws {
        #expect(throws: QRCode.GenerationError.self) { try QRCode(text: "") }
        #expect(throws: QRCode.GenerationError.self) { try QRCode(text: String(repeating: "a", count: 2_001)) }
        #expect(throws: QRCode.GenerationError.self) { try QRCode(text: String(repeating: "你", count: 667)) }
        #expect(try !QRCode(text: String(repeating: "a", count: 2_000)).pngData.isEmpty)
        #expect(try !QRCode(text: String(repeating: "你", count: 666)).pngData.isEmpty)
    }

    @Test func generatorIsSearchableAsATool() {
        for query in ["qr", "QR Code", "qrcode", "generator"] {
            #expect(ApplicationSearch.filter([LauncherItem.qrCode], query: query) == [.qrCode])
        }
        #expect(LauncherItem.qrCode.kind == "Tool")
    }
}
