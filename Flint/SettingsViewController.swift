import AppKit
import ServiceManagement

@MainActor
final class SettingsViewController: NSViewController {
    private enum Section: Int, CaseIterable {
        case general, shortcuts
        var title: String { self == .general ? "General" : "Shortcuts" }
        var symbol: String { self == .general ? "gearshape" : "command" }
        var subtitle: String {
            self == .general ? "A few small things to make Flint yours." : "Find your way around Flint."
        }
    }

    private let preferences: LauncherPreferences
    private let onShortcutChange: (LauncherShortcut) -> Bool
    private let onRecordingStateChange: (Bool) -> Void
    private let shortcutRecorder = ShortcutRecorder(frame: .zero)
    private let statusLabel = Appearance.label("", size: 12, color: .systemRed)
    private let loginSwitch = NSSwitch()
    private let loginStatus = Appearance.label("", size: 11, color: Appearance.muted)
    private let loginSettingsButton = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private var activationObserver: NSObjectProtocol?
    private let content = NSStackView()
    private var sectionButtons: [NSButton] = []
    private var selectionSurfaces: [NSView] = []
    private let shortcutReference = KeyboardHintView(.text(""))
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    init(preferences: LauncherPreferences, onShortcutChange: @escaping (LauncherShortcut) -> Bool,
         onRecordingStateChange: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.onShortcutChange = onShortcutChange
        self.onRecordingStateChange = onRecordingStateChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:onShortcutChange:)") }

    override func loadView() {
        view = AppearanceSurfaceView(fillColor: .windowBackgroundColor)
        view.frame = NSRect(x: 0, y: 0, width: 860, height: 590)
        let sidebar = makeSidebar()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 22
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)
        view.addSubview(content)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 204),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 32),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 62),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -28)
        ])
        configureRecorder()
        configureLoginItem()
        showSection(.general)
    }

    private func configureLoginItem() {
        loginSwitch.target = self
        loginSwitch.action = #selector(changeLoginItem)
        loginSwitch.setAccessibilityLabel("Launch at login")
        loginStatus.maximumNumberOfLines = 3
        loginStatus.lineBreakMode = .byWordWrapping
        loginSettingsButton.bezelStyle = .rounded
        loginSettingsButton.target = self
        loginSettingsButton.action = #selector(openLoginSettings)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLoginItem() }
        }
        refreshLoginItem()
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    private func refreshLoginItem(error: String? = nil) {
        let status = SMAppService.mainApp.status
        loginSwitch.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginSettingsButton.isHidden = status != .requiresApproval
        loginStatus.textColor = error == nil ? Appearance.muted : .systemRed
        loginStatus.stringValue = error ?? loginStatusMessage(for: status)
    }

    private func loginStatusMessage(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "Flint will be ready in the menu bar when you log in."
        case .requiresApproval:
            return "Allow Flint in System Settings → General → Login Items."
        default:
            return "Flint won’t start automatically when you log in."
        }
    }

    @objc private func changeLoginItem() {
        do {
            if loginSwitch.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItem()
        } catch {
            refreshLoginItem(error: "Couldn’t change launch at login. \(error.localizedDescription)")
        }
    }

    @objc private func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        let heading = label("SETTINGS", size: 10, weight: .semibold)
        let navigation = verticalStack([heading], spacing: 8)
        navigation.setCustomSpacing(14, after: heading)
        for section in Section.allCases {
            let button = NSButton(title: "  \(section.title)", target: self, action: #selector(selectSection(_:)))
            button.isBordered = false
            button.alignment = .left
            button.imageHugsTitle = true
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.contentTintColor = .labelColor
            button.tag = section.rawValue
            button.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel(section.title)
            sectionButtons.append(button)
            let row = NSView()
            let selection = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 0.27, alpha: 1) : NSColor(white: 0.84, alpha: 1)
            })
            selection.layer?.cornerRadius = 8
            selectionSurfaces.append(selection)
            [selection, button].forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview($0)
            }
            navigation.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: navigation.widthAnchor),
                row.heightAnchor.constraint(equalToConstant: 36),
                selection.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                selection.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                selection.topAnchor.constraint(equalTo: row.topAnchor),
                selection.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
                button.topAnchor.constraint(equalTo: row.topAnchor),
                button.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ])
        }
        let identity = Appearance.stack([
            Appearance.symbol("flame.fill", size: 17, color: Appearance.accent),
            label("Flint", size: 12, weight: .semibold, color: Appearance.text),
            Appearance.spacer(), label(version, size: 11)
        ])
        let divider = AppearanceSurfaceView(fillColor: .separatorColor)
        [navigation, identity, divider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 66),
            identity.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            identity.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -22),
            identity.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24),
            divider.widthAnchor.constraint(equalToConstant: 0.5),
            divider.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: sidebar.topAnchor),
            divider.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])
        return sidebar
    }

    private func configureRecorder() {
        shortcutRecorder.onShortcutChange = { [weak self] in self?.applyShortcut($0) }
        shortcutRecorder.onRecordingStateChange = onRecordingStateChange
        shortcutRecorder.onValidationError = { [weak self] in self?.showError($0) }
        shortcutRecorder.widthAnchor.constraint(equalToConstant: 154).isActive = true
        shortcutRecorder.controlSize = .large
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setAccessibilityIdentifier("shortcutStatus")
    }

    @objc private func selectSection(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        cancelRecording()
        showSection(section)
    }

    private func showSection(_ section: Section) {
        for (button, selection) in zip(sectionButtons, selectionSurfaces) {
            selection.isHidden = button.tag != section.rawValue
            button.setAccessibilityValue(button.tag == section.rawValue ? "Selected" : "")
        }
        content.arrangedSubviews.forEach {
            content.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        addContent(verticalStack([
            label(section.title, size: 25, weight: .bold, color: Appearance.text),
            label(section.subtitle, size: 12)
        ], spacing: 7))
        if section == .general { addGeneralContent() } else { addShortcutReference() }
    }

    private func addGeneralContent() {
        let icon = Appearance.symbol("flame.fill", size: 29, color: Appearance.accent)
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let identity = verticalStack([
            label("Flint", size: 17, weight: .semibold, color: Appearance.text),
            label("A little spark. A faster start.", size: 12)
        ], spacing: 5)
        addContent(card([
            paddedRow(Appearance.stack([icon, identity, Appearance.spacer(),
                                       label("Version \(version)", size: 11)], spacing: 14), height: 84)
        ]))
        let restore = NSButton(title: "Restore Default", target: self, action: #selector(restoreDefault))
        restore.bezelStyle = .rounded
        let activation = card([
            settingRow("Launcher shortcut", detail: "Show or hide Flint from any app.", control: shortcutRecorder),
            settingRow("Default shortcut", detail: "Return to Command–Space.", control: restore)
        ])
        let section = verticalStack([
            label("Activation", size: 12, weight: .semibold), activation
        ], spacing: 10)
        addContent(section)
        let instructions = label("Click the shortcut, then press a key combination. Escape cancels.", size: 11)
        instructions.maximumNumberOfLines = 2
        instructions.lineBreakMode = .byWordWrapping
        content.setCustomSpacing(12, after: section)
        addContent(verticalStack([instructions, statusLabel], spacing: 8))
        addContent(card([
            settingRow("Launch at login", detail: "Start Flint automatically when you log in.", control: loginSwitch)
        ]))
        addContent(verticalStack([loginStatus, loginSettingsButton], spacing: 8))
        addContent(label("Changes save automatically.", size: 11))
    }

    private func addShortcutReference() {
        shortcutReference.hint = .text(preferences.shortcut.title)
        addContent(card([
            referenceRow("Show or hide Flint", control: shortcutReference),
            referenceRow("Select a result", keys: [.upArrow, .downArrow]),
            referenceRow("Open application or run action", keys: [.returnKey]),
            referenceRow("Dismiss Flint", keys: [.escape]),
            referenceRow("Refresh applications", keys: [.command, .text("R")]),
            referenceRow("Open Settings", keys: [.command, .text(",")])
        ]))
        addContent(label("Change the launcher shortcut in General.", size: 11))
    }

    private func referenceRow(_ title: String, keys: [KeyboardHint]) -> NSView {
        referenceRow(title, control: Appearance.stack(keys.map { KeyboardHintView($0) }, spacing: 5))
    }

    private func referenceRow(_ title: String, control: NSView) -> NSView {
        paddedRow(Appearance.stack([
            label(title, size: 13, color: Appearance.text), Appearance.spacer(), control
        ], spacing: 16), height: 53)
    }

    private func settingRow(_ title: String, detail: String, control: NSView) -> NSView {
        let labels = verticalStack([
            label(title, size: 13, weight: .medium, color: Appearance.text),
            label(detail, size: 11)
        ], spacing: 5)
        return paddedRow(Appearance.stack([labels, Appearance.spacer(), control], spacing: 16), height: 78)
    }

    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                       color: NSColor = Appearance.muted) -> NSTextField {
        let label = Appearance.label(text, size: size, weight: weight, color: color)
        label.alignment = .left
        return label
    }

    private func addContent(_ child: NSView) {
        content.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func paddedRow(_ content: NSView, height: CGFloat) -> NSView {
        let row = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: height),
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            content.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func card(_ rows: [NSView]) -> NSView {
        let surface = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        })
        surface.layer?.cornerRadius = 14
        let stack = verticalStack([], spacing: 0)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let divider = paddedRow(Appearance.separator(), height: 1)
                stack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            stack.topAnchor.constraint(equalTo: surface.topAnchor),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        return surface
    }

    func refresh(shortcutIsRegistered: Bool) {
        _ = view
        selectCurrentShortcut()
        refreshLoginItem()
        showError(shortcutIsRegistered ? nil : "The shortcut couldn’t be registered. Try a different shortcut.")
        if !shortcutIsRegistered { showSection(.general) }
    }

    private func selectCurrentShortcut() {
        shortcutRecorder.shortcut = preferences.shortcut
        shortcutReference.hint = .text(preferences.shortcut.title)
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
        showError(registered ? nil : "The shortcut couldn’t be registered. Try a different shortcut.")
    }
}
