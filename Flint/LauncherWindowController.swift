import AppKit
import Carbon

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    #if FLINT_APPEARANCE_CHECKS
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        AppearanceCheckWindows.showsWindows ? super.constrainFrameRect(frameRect, to: screen) : frameRect
    }
    #endif
}

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private let applicationsController = ApplicationsViewController()
    private let preferences: LauncherPreferences
    private let keepsOpenOnFocusLoss: Bool
    private var displayMode: LauncherDisplayMode?
    private var placement: LauncherPlacement?
    private var allowsResizeAnimation = false
    private var transitionGeneration = 0
    private var visibilityGeneration = 0
    private(set) var isPresented = false
    var onShowSettings: (() -> Void)? {
        didSet { applicationsController.onShowSettings = onShowSettings }
    }
    var onShowTranslationSettings: (() -> Void)? {
        didSet { applicationsController.onShowTranslationSettings = onShowTranslationSettings }
    }

    init(preferences: LauncherPreferences = LauncherPreferences(), keepsOpenOnFocusLoss: Bool = false) {
        self.preferences = preferences
        self.keepsOpenOnFocusLoss = keepsOpenOnFocusLoss
        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        super.init(window: panel)
        panel.title = "Flint"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.appearance = nil
        panel.contentViewController = applicationsController
        panel.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(selectABCInputSource),
                                               name: NSApplication.didBecomeActiveNotification, object: NSApp)
        applicationsController.onDismiss = { [weak self] in self?.hideLauncher() }
        applicationsController.onDisplayModeChange = { [weak self] in self?.setDisplayMode($0) }
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func showLauncher() {
        if applicationsController.isPresentingDialog {
            setPresented(true)
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard window != nil, let screen else { return }
        allowsResizeAnimation = false
        #if FLINT_APPEARANCE_CHECKS
        let visibleFrame = AppearanceCheckWindows.frame(for: screen.visibleFrame)
        #else
        let visibleFrame = screen.visibleFrame
        #endif
        placement = LauncherPlacement(visibleFrame: visibleFrame,
                                      expandedSize: NSSize(width: 760, height: 560))
        displayMode = nil
        applicationsController.resetSearch()
        setPresented(true)
        allowsResizeAnimation = true
    }

    func hideLauncher() {
        guard isPresented else { return }
        applicationsController.cancelDialog()
        applicationsController.cancelTranslation()
        setPresented(false)
    }

    private func setPresented(_ presented: Bool) {
        guard let window else { return }
        isPresented = presented
        visibilityGeneration += 1
        let generation = visibilityGeneration
        window.ignoresMouseEvents = !presented
        if presented {
            if !window.isVisible { window.alphaValue = 0 }
            #if FLINT_APPEARANCE_CHECKS
            AppearanceCheckWindows.show(window)
            #else
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            #endif
            selectABCInputSource()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Appearance.launcherVisibilityDuration(appearing: presented)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = presented ? 1 : 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, self.visibilityGeneration == generation, !self.isPresented else { return }
                window?.orderOut(nil)
            }
        }
    }

    private func setDisplayMode(_ mode: LauncherDisplayMode) {
        guard let window, let placement, displayMode != mode else { return }
        displayMode = mode
        transitionGeneration += 1
        let generation = transitionGeneration
        let height = mode.height
        let frame = placement.frame(height: height)
        let duration = allowsResizeAnimation ? Appearance.launcherTransitionDuration(for: window) : 0
        // Keep the backing window still while the viewport reveals or clips the glass.
        if height > window.frame.height || duration == 0 {
            window.setFrame(frame, display: true)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        Appearance.revealLauncher(height: height, on: applicationsController.view, duration: duration) { [weak self, weak window] in
            guard let self, self.transitionGeneration == generation, let window, window.frame != frame else { return }
            window.setFrame(frame, display: true)
        }
    }

    func refreshApplications() { applicationsController.refreshApplications() }

    func windowDidBecomeKey(_ notification: Notification) {
        selectABCInputSource()
    }

    @objc private func selectABCInputSource() {
        // Activation and key-window notifications can arrive in either order.
        guard preferences.switchToABC, isPresented, NSApp.isActive, window?.isKeyWindow == true else { return }
        let properties = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
        guard let sources = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else { return }
        TISSelectInputSource(source)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !keepsOpenOnFocusLoss, !applicationsController.isPresentingDialog else { return }
        hideLauncher()
    }
}
