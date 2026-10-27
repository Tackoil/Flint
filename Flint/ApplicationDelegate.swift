import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var launcher: LauncherWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: LauncherHotKey?
    private let preferences = LauncherPreferences()
    private var settingsController: SettingsWindowController?
    private var showLauncherItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let keepsOpenOnFocusLoss = ProcessInfo.processInfo.arguments.contains("--keep-open")
        launcher = LauncherWindowController(keepsOpenOnFocusLoss: keepsOpenOnFocusLoss)
        hotKey = makeHotKey(for: preferences.shortcut)
        installStatusItem()
        launcher?.onShowSettings = { [weak self] in self?.showSettings() }
        showLauncher()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncher()
        return true
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let applicationItem = menu.addItem(withTitle: "Flint", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "Flint")
        let settings = applicationMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Flint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu

        let fileItem = menu.addItem(withTitle: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let refresh = fileMenu.addItem(withTitle: "Refresh Applications", action: #selector(refreshApplications), keyEquivalent: "r")
        refresh.target = self
        fileItem.submenu = fileMenu

        let editItem = menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Flint")
        let menu = NSMenu()
        let show = menu.addItem(withTitle: "Show Flint", action: #selector(showLauncher), keyEquivalent: "")
        show.target = self
        showLauncherItem = show
        updateShortcutMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Flint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showLauncher() { launcher?.showLauncher() }
    @objc private func refreshApplications() { launcher?.refreshApplications() }

    @objc private func showSettings() {
        launcher?.window?.orderOut(nil)
        if settingsController == nil {
            settingsController = SettingsWindowController(preferences: preferences, onShortcutChange: { [weak self] shortcut in
                self?.changeShortcut(to: shortcut) ?? false
            }, onRecordingStateChange: { [weak self] recording in
                self?.hotKey?.setEnabled(!recording)
                self?.updateShortcutMenu()
            })
        }
        settingsController?.cancelRecording()
        settingsController?.showSettings(shortcutIsRegistered: hotKey?.isRegistered == true)
    }

    private func makeHotKey(for shortcut: LauncherShortcut) -> LauncherHotKey {
        LauncherHotKey(shortcut: shortcut) { [weak self] in self?.toggleLauncher() }
    }

    private func changeShortcut(to shortcut: LauncherShortcut) -> Bool {
        hotKey = nil
        let replacement = makeHotKey(for: shortcut)
        guard replacement.isRegistered else {
            hotKey = makeHotKey(for: preferences.shortcut)
            updateShortcutMenu()
            return false
        }
        hotKey = replacement
        preferences.shortcut = shortcut
        updateShortcutMenu()
        return true
    }

    private func updateShortcutMenu() {
        showLauncherItem?.keyEquivalent = hotKey?.isRegistered == true ? preferences.shortcut.characters.lowercased() : ""
        showLauncherItem?.keyEquivalentModifierMask = preferences.shortcut.menuModifiers
    }

    private func toggleLauncher() {
        guard let launcher else { return }
        if launcher.window?.isKeyWindow == true {
            launcher.window?.orderOut(nil)
        } else {
            launcher.showLauncher()
        }
    }
}
