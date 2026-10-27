import AppKit

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private let applicationsController = ApplicationsViewController()
    private let keepsOpenOnFocusLoss: Bool
    var onShowSettings: (() -> Void)? {
        didSet { applicationsController.onShowSettings = onShowSettings }
    }

    init(keepsOpenOnFocusLoss: Bool = false) {
        self.keepsOpenOnFocusLoss = keepsOpenOnFocusLoss
        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        super.init(window: panel)
        panel.title = "Flint"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = !keepsOpenOnFocusLoss
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = applicationsController
        panel.delegate = self
        panel.center()
        applicationsController.onDismiss = { [weak panel] in panel?.orderOut(nil) }
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func showLauncher() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        applicationsController.resetSearch()
    }

    func refreshApplications() { applicationsController.refreshApplications() }

    func windowDidResignKey(_ notification: Notification) {
        guard !keepsOpenOnFocusLoss, window?.attachedSheet == nil else { return }
        window?.orderOut(nil)
    }
}
