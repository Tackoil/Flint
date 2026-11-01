import AppKit

final class SettingsPopoverTransition: NSAnimation {
    var completion: (() -> Void)?
    private let update: (CGFloat) -> Void

    init(duration: TimeInterval, appearing: Bool, update: @escaping (CGFloat) -> Void) {
        self.update = update
        super.init(duration: duration, animationCurve: appearing ? .easeOut : .easeIn)
        animationBlockingMode = .nonblocking
        frameRate = 120
    }

    required init?(coder: NSCoder) { fatalError("Use init(duration:appearing:update:)") }

    override var currentProgress: NSAnimation.Progress {
        didSet {
            update(CGFloat(currentValue))
            if currentProgress >= 1 {
                let finished = completion
                completion = nil
                finished?()
            }
        }
    }
}

extension SettingsActionsPopover {
    var isTransitioning: Bool { transition != nil }

    static func transitionDuration(appearing: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : appearing ? 0.18 : 0.12
    }

    func setTargetFrame(_ frame: NSRect) {
        targetFrame = frame
        displayTransition(transitionProgress)
    }

    func present(animated: Bool = true) {
        displayTransition(0)
        animate(to: 1, animated: animated, completion: {})
    }

    func dismiss(animated: Bool = true, completion: @escaping () -> Void) {
        prepareForDismissal()
        animate(to: 0, animated: animated, completion: completion)
    }

    private func animate(to target: CGFloat, animated: Bool, completion: @escaping () -> Void) {
        transition?.stop()
        transition = nil
        let initial = transitionProgress
        let reduceMotion = !animated || window?.isVisible != true || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = Self.transitionDuration(appearing: target > 0, reduceMotion: reduceMotion) * Double(abs(target - initial))
        guard duration > 0 else {
            displayTransition(target)
            completion()
            return
        }
        let animation = SettingsPopoverTransition(duration: duration, appearing: target > 0) { [weak self] progress in
            self?.displayTransition(initial + (target - initial) * progress)
        }
        animation.completion = { [weak self, weak animation] in
            guard let self, transition === animation else { return }
            transition = nil
            displayTransition(target)
            completion()
        }
        transition = animation
        animation.start()
    }

    private func displayTransition(_ progress: CGFloat) {
        transitionProgress = min(max(progress, 0), 1)
        // Move the actual view so native glass rendering and hit testing share its geometry.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            frame = targetFrame.offsetBy(dx: 0, dy: -8 * (1 - transitionProgress))
            alphaValue = transitionProgress
            CATransaction.commit()
        }
    }
}
