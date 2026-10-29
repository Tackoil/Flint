import AppKit

enum LauncherLayout {
    static let cornerRadius: CGFloat = 28
    static let contentInset: CGFloat = 16
    static let floatingControlSize: CGFloat = 36
    static var floatingControlRadius: CGFloat { floatingControlSize / 2 }
    // Match the controls' centers to the centers of the bottom corner arcs.
    static var floatingControlInset: CGFloat { cornerRadius - floatingControlRadius }
    static var footerHeight: CGFloat { cornerRadius * 2 }
    static let resultRowHeight: CGFloat = 40
    static let applicationIconSize: CGFloat = 28
    static let actionIconSize: CGFloat = 18
    static let rowSpacing: CGFloat = 16
    static var rowHorizontalInset: CGFloat { iconCenterX - applicationIconSize / 2 }
    static var iconCenterX: CGFloat { cornerRadius }
    static var textLeading: CGFloat { rowHorizontalInset + applicationIconSize + rowSpacing }
}

private final class LauncherViewport: NSView {
    override var isFlipped: Bool { true }
}

private final class LauncherSurfaceView: NSView {
    private let materialView: NSView
    private let materialHeight: CGFloat
    private let viewport = LauncherViewport()

    init(materialView: NSView) {
        self.materialView = materialView
        materialHeight = materialView.frame.height
        super.init(frame: materialView.frame)
        wantsLayer = true
        layer?.masksToBounds = true
        viewport.frame = bounds
        viewport.autoresizingMask = [.width]
        viewport.wantsLayer = true
        viewport.layer?.masksToBounds = true
        addSubview(viewport)
        viewport.addSubview(materialView)
    }

    required init?(coder: NSCoder) { fatalError("Use init(materialView:)") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        // A top-left origin keeps the glass stationary as the viewport height changes.
        let frame = NSRect(x: 0, y: 0, width: bounds.width, height: materialHeight)
        guard materialView.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        materialView.frame = frame
        CATransaction.commit()
    }

    func setCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = radius
        viewport.layer?.cornerRadius = radius
        if #available(macOS 26.0, *), let glass = materialView as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            materialView.layer?.cornerRadius = radius
        }
    }

    func reveal(height: CGFloat, duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        let size = NSSize(width: bounds.width, height: height)
        guard duration > 0 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            viewport.setFrameSize(size)
            CATransaction.commit()
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            viewport.animator().setFrameSize(size)
        } completionHandler: {
            Task { @MainActor in completion() }
        }
    }
}

final class AppearanceSurfaceView: NSView {
    private let fillColor: NSColor
    private let borderColor: NSColor

    init(fillColor: NSColor, borderColor: NSColor = .clear) {
        self.fillColor = fillColor
        self.borderColor = borderColor
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(fillColor:borderColor:)") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
            layer?.borderColor = borderColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class ActionGroupResizeAnimation: NSAnimation {
    private let update: (CGFloat) -> Void

    init(duration: TimeInterval, update: @escaping (CGFloat) -> Void) {
        self.update = update
        super.init(duration: duration, animationCurve: .easeInOut)
        animationBlockingMode = .nonblocking
        frameRate = 120
    }

    required init?(coder: NSCoder) { fatalError("Use init(duration:update:)") }

    override var currentProgress: NSAnimation.Progress {
        didSet { update(CGFloat(currentValue)) }
    }
}

final class ActionGroupView: NSView {
    let surface: NSView
    private let content: NSView
    private let viewport = NSView()
    private var resizeAnimation: ActionGroupResizeAnimation?
    private(set) var displayedWidth: CGFloat = 0
    private(set) var targetWidth: CGFloat = 0

    init(surface: NSView, content: NSView) {
        self.surface = surface
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        viewport.wantsLayer = true
        viewport.layer?.masksToBounds = true
        viewport.layer?.cornerRadius = LauncherLayout.floatingControlRadius
        addSubview(surface)
        addSubview(viewport)
        content.translatesAutoresizingMaskIntoConstraints = false
        viewport.addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: LauncherLayout.floatingControlSize),
            content.trailingAnchor.constraint(equalTo: viewport.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: viewport.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(surface:content:)") }

    override func layout() {
        super.layout()
        let width = min(content.fittingSize.width + 26, bounds.width)
        if width != targetWidth {
            resize(to: width)
        } else {
            display(width: displayedWidth)
        }
    }

    private func resize(to width: CGFloat) {
        resizeAnimation?.stop()
        resizeAnimation = nil
        targetWidth = width
        let duration = Appearance.launcherTransitionDuration(for: window)
        guard displayedWidth > 0, duration > 0 else {
            display(width: width)
            return
        }
        let initialWidth = displayedWidth
        let animation = ActionGroupResizeAnimation(duration: duration) { [weak self] progress in
            self?.display(width: initialWidth + (width - initialWidth) * progress)
        }
        resizeAnimation = animation
        animation.start()
    }

    private func display(width: CGFloat) {
        displayedWidth = width
        let frame = NSRect(x: bounds.maxX - width, y: 0, width: width, height: bounds.height)
        // Resize the actual native glass on each frame. Animating only its backing
        // layer leaves the glass renderer and its hit-testing geometry out of sync.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            surface.frame = frame
            viewport.frame = frame
            surface.layoutSubtreeIfNeeded()
            viewport.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
    }
}

enum Appearance {
    static let muted = NSColor.secondaryLabelColor
    static let text = NSColor.labelColor
    static let accent = NSColor(srgbRed: 1, green: 0.43, blue: 0.31, alpha: 1)

    static func launcherTransitionDuration(for window: NSWindow?) -> TimeInterval {
        guard window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 0 }
        return 0.24
    }

    static func launcherVisibilityDuration(appearing: Bool) -> TimeInterval {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 0 }
        return appearing ? 0.16 : 0.12
    }

    static func launcherSurface(content: NSView) -> NSView {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.style = .regular
            glass.tintColor = nil
            glass.contentView = content
            return LauncherSurfaceView(materialView: glass)
        }
        let effect = NSVisualEffectView(frame: content.frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        effect.addSubview(content)
        return LauncherSurfaceView(materialView: effect)
    }

    static func setLauncherCornerRadius(_ radius: CGFloat, on surface: NSView) {
        (surface as? LauncherSurfaceView)?.setCornerRadius(radius)
    }

    @MainActor static func revealLauncher(height: CGFloat, on surface: NSView, duration: TimeInterval,
                               completion: @escaping @MainActor () -> Void) {
        guard let surface = surface as? LauncherSurfaceView else {
            completion()
            return
        }
        surface.reveal(height: height, duration: duration, completion: completion)
    }

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

    static func actionGroup(content: NSView) -> NSView {
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = LauncherLayout.floatingControlRadius
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            surface = glass
        } else {
            let background = AppearanceSurfaceView(fillColor: .quaternaryLabelColor, borderColor: .separatorColor)
            background.layer?.cornerRadius = LauncherLayout.floatingControlRadius
            background.layer?.borderWidth = 0.5
            surface = background
        }
        return ActionGroupView(surface: surface, content: content)
    }

    static func separator() -> NSView {
        let view = AppearanceSurfaceView(fillColor: .separatorColor)
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
