import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settingsController: SettingsViewController

    init(preferences: LauncherPreferences, onShortcutChange: @escaping (LauncherShortcut) -> Bool,
         onRecordingStateChange: @escaping (Bool) -> Void) {
        settingsController = SettingsViewController(
            preferences: preferences, onShortcutChange: onShortcutChange, onRecordingStateChange: onRecordingStateChange
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init(window: window)
        window.title = "Flint Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 800, height: 560)
        window.isReleasedWhenClosed = false
        window.appearance = nil
        window.contentViewController = settingsController
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:onShortcutChange:)") }

    func cancelRecording() { settingsController.cancelRecording() }

    func showSettings(shortcutIsRegistered: Bool) {
        settingsController.refresh(shortcutIsRegistered: shortcutIsRegistered)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
