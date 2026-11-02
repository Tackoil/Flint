import AppKit

final class ColorSwatchView: NSView {
    var color = NSColor.clear { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor(white: 0.95, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0.75, alpha: 1).setFill()
        for row in 0..<8 {
            for column in 0..<8 where (row + column).isMultiple(of: 2) {
                NSRect(x: column * 6, y: row * 6, width: 6, height: 6).fill()
            }
        }
        color.setFill()
        bounds.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}

class ResultPreviewStripView: NSView {
    private let rightFade = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.mask = rightFade
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rightFade.frame = bounds
        rightFade.startPoint = CGPoint(x: 0, y: 0.5)
        rightFade.endPoint = CGPoint(x: 1, y: 0.5)
        rightFade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        rightFade.locations = [0, NSNumber(value: max(0, 1 - 96 / max(bounds.width, 1))), 1]
        CATransaction.commit()
    }
}

final class ColorFormatPreviewView: NSStackView {
    private let valueLabel = Appearance.label("", size: 22, weight: .medium, color: .labelColor)
    private let formatLabel = Appearance.label("", size: 12, color: .secondaryLabelColor)
    private let gamutLabel = Appearance.label("", size: 11, color: .secondaryLabelColor)
    private(set) var format: ColorConversion.Format?
    private(set) var isPrimary = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        for label in [formatLabel, valueLabel, gamutLabel] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            addArrangedSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ conversion: ColorConversion, isPrimary: Bool) {
        self.isPrimary = isPrimary
        format = conversion.format
        formatLabel.stringValue = conversion.format.title
        valueLabel.stringValue = conversion.answer
        valueLabel.font = .monospacedSystemFont(ofSize: conversion.answer.count > 40 ? 17 : 22, weight: .medium)
        valueLabel.toolTip = conversion.answer
        gamutLabel.stringValue = conversion.format.usesSRGB ? "Clipped to sRGB" : "Preview clipped to sRGB"
        gamutLabel.isHidden = !isPrimary || !conversion.isOutsideSRGB
        alphaValue = isPrimary ? 1 : 0.4
        toolTip = conversion.answer
    }
}

final class ColorResultView: NSView {
    private let swatch = ColorSwatchView()
    private let strip = ResultPreviewStripView()
    private var outputs = (0...ColorConversion.Format.allCases.count).map { _ in ColorFormatPreviewView() }
    private let row = NSStackView()
    private lazy var rowLeading = row.leadingAnchor.constraint(equalTo: strip.leadingAnchor)
    private var previousConversion: ColorConversion?

    private struct DisplayedOutput {
        let position: CGPoint
        let opacity: Float
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for output in outputs {
            output.wantsLayer = true
            row.addArrangedSubview(output)
        }
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 32
        row.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(row)
        for item in [swatch, strip] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            swatch.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 48),
            swatch.heightAnchor.constraint(equalToConstant: 48),
            strip.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 20),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            rowLeading,
            row.centerYAnchor.constraint(equalTo: strip.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(_ conversion: ColorConversion) {
        guard conversion != previousConversion else { return }
        let direction = switchingDirection(to: conversion)
        let duration = direction == 0 ? 0 : Appearance.launcherTransitionDuration(for: window)
        let displayed = duration > 0 ? displayedOutputs() : [:]
        clearOutputAnimations()
        rotateOutputs(direction: direction)
        updateOutputs(conversion)
        rowLeading.constant = -(outputs[0].fittingSize.width + row.spacing)
        layoutSubtreeIfNeeded()
        if duration > 0 { animateOutputs(from: displayed, direction: direction, duration: duration) }
        previousConversion = conversion
    }

    private func switchingDirection(to conversion: ColorConversion) -> Int {
        guard let previous = previousConversion, previous.expression == conversion.expression else { return 0 }
        if previous.format.shifted(by: 1) == conversion.format { return 1 }
        if previous.format.shifted(by: -1) == conversion.format { return -1 }
        return 0
    }

    private func rotateOutputs(direction: Int) {
        guard direction != 0 else { return }
        let output = direction > 0 ? outputs.removeFirst() : outputs.removeLast()
        let index = direction > 0 ? outputs.count : 0
        outputs.insert(output, at: index)
        row.insertArrangedSubview(output, at: index)
    }

    private func updateOutputs(_ conversion: ColorConversion) {
        let rgb = conversion.previewRGB
        swatch.color = NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: conversion.alpha)
        swatch.setAccessibilityLabel("Color preview: \(conversion.expression)")
        for (index, output) in outputs.enumerated() {
            var preview = conversion
            preview.format = conversion.format.shifted(by: index - 1)
            output.configure(preview, isPrimary: index == 1)
            output.setAccessibilityHidden(index == 0)
        }
        toolTip = conversion.answer
    }

    private func displayedOutputs() -> [ObjectIdentifier: DisplayedOutput] {
        guard let reference = strip.layer else { return [:] }
        return Dictionary(uniqueKeysWithValues: outputs.compactMap { output in
            guard let layer = output.layer, let parent = layer.superlayer else { return nil }
            let visible = layer.presentation() ?? layer
            let position = reference.convert(visible.position, from: visible.superlayer ?? parent)
            return (ObjectIdentifier(output), DisplayedOutput(position: position, opacity: visible.opacity))
        })
    }

    private func clearOutputAnimations() {
        for output in outputs {
            output.layer?.removeAnimation(forKey: "colorOutputPosition")
            output.layer?.removeAnimation(forKey: "colorOutputOpacity")
        }
    }

    private func animateOutputs(from displayed: [ObjectIdentifier: DisplayedOutput], direction: Int, duration: TimeInterval) {
        let recycledIndex = direction > 0 ? outputs.count - 1 : 0
        for (index, output) in outputs.enumerated() where index != recycledIndex {
            guard let layer = output.layer, let parent = layer.superlayer, let reference = strip.layer,
                  let previous = displayed[ObjectIdentifier(output)] else { continue }
            addAnimation(to: layer, keyPath: "position", key: "colorOutputPosition",
                         from: parent.convert(previous.position, from: reference), to: layer.position, duration: duration)
            addAnimation(to: layer, keyPath: "opacity", key: "colorOutputOpacity",
                         from: previous.opacity, to: layer.opacity, duration: duration)
        }
    }

    private func addAnimation(to layer: CALayer, keyPath: String, key: String, from: Any, to: Any, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }
}
