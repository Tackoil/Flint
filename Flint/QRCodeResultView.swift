import AppKit

private final class QRCodeImageView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() { layer?.contents = image }
}

@MainActor
final class QRCodeResultView: NSView {
    private let imageView = QRCodeImageView()
    private let placeholder = Appearance.symbol("qrcode", size: 80, color: .tertiaryLabelColor)
    private let message = Appearance.label("", size: 14, color: .secondaryLabelColor)
    private(set) var code: QRCode?
    private var previousText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        message.alignment = .center
        message.maximumNumberOfLines = 2
        imageView.setAccessibilityElement(true)
        imageView.setAccessibilityRole(.image)
        imageView.setAccessibilityLabel("Generated QR code")
        for child in [imageView, placeholder, message] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 256),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            placeholder.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 80),
            placeholder.heightAnchor.constraint(equalToConstant: 80),
            message.topAnchor.constraint(equalTo: placeholder.bottomAnchor, constant: 16),
            message.centerXAnchor.constraint(equalTo: centerXAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -64)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(text: String) {
        guard text != previousText else { return }
        previousText = text
        do {
            let generated = try QRCode(text: text)
            code = generated
            imageView.image = generated.image
            message.stringValue = ""
        } catch {
            code = nil
            imageView.image = nil
            message.stringValue = error.localizedDescription
        }
        imageView.isHidden = code == nil
        placeholder.isHidden = code != nil
        message.isHidden = code != nil
    }
}
