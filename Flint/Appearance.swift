import AppKit

enum Appearance {
    static let background = NSColor(srgbRed: 0.085, green: 0.09, blue: 0.105, alpha: 0.97)
    static let muted = NSColor(white: 0.50, alpha: 1)
    static let text = NSColor(white: 0.93, alpha: 1)
    static let accent = NSColor(srgbRed: 1, green: 0.43, blue: 0.31, alpha: 1)

    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = muted) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        image.contentTintColor = color
        return image
    }

    static func stack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    static func keycap(_ text: String) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 1, alpha: 0.055).cgColor
        view.layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor
        view.layer?.borderWidth = 0.5
        view.layer?.cornerRadius = 4
        let text = label(text, size: 11, weight: .medium, color: NSColor(white: 0.67, alpha: 1))
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 21),
            view.heightAnchor.constraint(equalToConstant: 21),
            text.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    static func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    static func button(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = muted
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
}
