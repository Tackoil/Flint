import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    private let preferences: LauncherPreferences
    private let onShortcutChange: (LauncherShortcut) -> Bool
    private let onRecordingStateChange: (Bool) -> Void
    private let shortcutRecorder = ShortcutRecorder(frame: .zero)
    private let statusLabel = Appearance.label("", size: 11, color: .systemRed)

    init(preferences: LauncherPreferences, onShortcutChange: @escaping (LauncherShortcut) -> Bool,
         onRecordingStateChange: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.onShortcutChange = onShortcutChange
        self.onRecordingStateChange = onRecordingStateChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:onShortcutChange:)") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 330))
        let title = Appearance.label("General", size: 23, weight: .semibold, color: Appearance.text)
        let subtitle = Appearance.label("Your launcher, your shortcut.", size: 12)
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 7
        let icon = Appearance.symbol("flame.fill", size: 30, color: Appearance.accent)
        let header = Appearance.stack([icon, heading, Appearance.spacer()], spacing: 16)

        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setAccessibilityIdentifier("shortcutStatus")
        let help = Appearance.label("Click the shortcut and press a key combination. Escape cancels. Changes save automatically.", size: 11)
        help.maximumNumberOfLines = 2
        help.lineBreakMode = .byWordWrapping
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let restoreButton = NSButton(title: "Restore Default", target: self, action: #selector(restoreDefault))
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .small
        let footer = Appearance.stack([Appearance.label("Flint · \(version)", size: 11), Appearance.spacer(), restoreButton])

        let stack = NSStackView(views: [header, shortcutCard(), help, statusLabel, NSView(), footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22)
        ])
    }

    private func shortcutCard() -> NSView {
        let title = Appearance.label("Launcher shortcut", size: 13, weight: .medium, color: Appearance.text)
        let subtitle = Appearance.label("Show or hide Flint from any app.", size: 11)
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 6
        shortcutRecorder.onShortcutChange = { [weak self] in self?.applyShortcut($0) }
        shortcutRecorder.onRecordingStateChange = onRecordingStateChange
        shortcutRecorder.onValidationError = { [weak self] in self?.showError($0) }
        shortcutRecorder.widthAnchor.constraint(equalToConstant: 177).isActive = true
        let row = Appearance.stack([labels, Appearance.spacer(), shortcutRecorder], spacing: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        let card = AppearanceSurfaceView(fillColor: .controlBackgroundColor, borderColor: .separatorColor)
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.addSubview(row)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 88),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    func refresh(shortcutIsRegistered: Bool) {
        _ = view
        selectCurrentShortcut()
        statusLabel.stringValue = "The shortcut couldn’t be registered. Try a different shortcut."
        statusLabel.isHidden = shortcutIsRegistered
    }

    private func selectCurrentShortcut() {
        shortcutRecorder.shortcut = preferences.shortcut
    }

    func cancelRecording() { shortcutRecorder.cancelRecording() }

    private func showError(_ message: String?) {
        statusLabel.stringValue = message ?? ""
        statusLabel.isHidden = message == nil
    }

    @objc private func restoreDefault() {
        cancelRecording()
        applyShortcut(.commandSpace)
    }

    private func applyShortcut(_ shortcut: LauncherShortcut) {
        let registered = onShortcutChange(shortcut)
        selectCurrentShortcut()
        statusLabel.stringValue = "The shortcut couldn’t be registered. Try a different shortcut."
        statusLabel.isHidden = registered
    }
}
