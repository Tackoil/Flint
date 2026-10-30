import AppKit
import ServiceManagement

@MainActor
final class SettingsViewController: NSViewController {
    private enum Section: Int, CaseIterable {
        case general, quickLinks, translation
        var title: String {
            switch self {
            case .general: return "General"
            case .quickLinks: return "Quick Links"
            case .translation: return "Translation"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .quickLinks: return "link"
            case .translation: return "character.bubble"
            }
        }
    }

    private let preferences: LauncherPreferences
    private let onShortcutChange: (LauncherShortcut) -> Bool
    private let onRecordingStateChange: (Bool) -> Void
    private let onMenuBarVisibilityChange: (Bool) -> Void
    private let shortcutRecorder = ShortcutRecorder(frame: .zero)
    private let statusLabel = Appearance.label("", size: 12, color: .systemRed)
    private let loginSwitch = NSSwitch()
    private let menuBarSwitch = NSSwitch()
    private let inputSourceSwitch = NSSwitch()
    private let loginStatus = Appearance.label("", size: 11, color: Appearance.muted)
    private let loginSettingsButton = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private var activationObserver: NSObjectProtocol?
    private let content = NSStackView()
    private var sectionButtons: [NSButton] = []
    private var selectionSurfaces: [NSView] = []
    private lazy var quickLinkSettings = QuickLinkSettingsView()
    private lazy var translationSettings = TranslationSettingsView()
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    init(preferences: LauncherPreferences, onShortcutChange: @escaping (LauncherShortcut) -> Bool,
         onRecordingStateChange: @escaping (Bool) -> Void,
         onMenuBarVisibilityChange: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.onShortcutChange = onShortcutChange
        self.onRecordingStateChange = onRecordingStateChange
        self.onMenuBarVisibilityChange = onMenuBarVisibilityChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:onShortcutChange:)") }

    override func loadView() {
        view = AppearanceSurfaceView(fillColor: .windowBackgroundColor)
        view.frame = NSRect(x: 0, y: 0, width: 720, height: 560)
        let sidebar = makeSidebar()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)
        view.addSubview(content)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 180),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 54),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        ])
        [loginSwitch, menuBarSwitch, inputSourceSwitch].forEach { $0.controlSize = .mini }
        configureRecorder()
        configureLoginItem()
        menuBarSwitch.target = self
        menuBarSwitch.action = #selector(changeMenuBarVisibility)
        menuBarSwitch.setAccessibilityLabel("Show in Menu Bar")
        menuBarSwitch.toolTip = "Show Flint’s flame icon in the menu bar."
        menuBarSwitch.state = preferences.showInMenuBar ? .on : .off
        configureInputSource()
        showSection(.general)
    }

    private func configureInputSource() {
        inputSourceSwitch.target = self
        inputSourceSwitch.action = #selector(changeInputSource)
        inputSourceSwitch.setAccessibilityLabel("Switch to ABC")
        inputSourceSwitch.toolTip = "Switch the input method to ABC whenever Flint opens or regains focus."
        inputSourceSwitch.state = preferences.switchToABC ? .on : .off
    }

    private func configureLoginItem() {
        loginSwitch.target = self
        loginSwitch.action = #selector(changeLoginItem)
        loginSwitch.setAccessibilityLabel("Open at Login")
        loginSwitch.toolTip = "Start Flint automatically when you log in."
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
        loginStatus.stringValue = error ?? "Allow Flint in System Settings → General → Login Items."
        loginStatus.isHidden = error == nil && status != .requiresApproval
    }

    @objc private func changeMenuBarVisibility() {
        preferences.showInMenuBar = menuBarSwitch.state == .on
        onMenuBarVisibilityChange(preferences.showInMenuBar)
    }

    @objc private func changeInputSource() {
        preferences.switchToABC = inputSourceSwitch.state == .on
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
        shortcutRecorder.controlSize = .small
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
        addContent(label(section.title, size: 20, weight: .bold, color: Appearance.text))
        if section == .general { addGeneralContent() }
        if section == .quickLinks {
            quickLinkSettings.reload()
            addContent(quickLinkSettings)
        }
        if section == .translation { addContent(translationSettings) }
    }

    func createQuickLink() {
        _ = view
        cancelRecording()
        showSection(.quickLinks)
        quickLinkSettings.addLink()
    }

    func showTranslationSettings() {
        _ = view
        cancelRecording()
        showSection(.translation)
    }

    private func addGeneralContent() {
        let restore = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise",
                                              accessibilityDescription: "Restore Default Shortcut")!,
                               target: self, action: #selector(restoreDefault))
        restore.bezelStyle = .rounded
        restore.imagePosition = .imageOnly
        restore.toolTip = "Restore default shortcut (Command–Space)."
        restore.setAccessibilityLabel("Restore Default Shortcut")
        restore.controlSize = .small
        restore.widthAnchor.constraint(equalToConstant: 24).isActive = true
        restore.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let shortcutControls = Appearance.stack([shortcutRecorder, restore], spacing: 8)
        let settings = card([
            settingRow("Open at Login", control: loginSwitch),
            settingRow("Show in Menu Bar", control: menuBarSwitch),
            settingRow("Switch to ABC", control: inputSourceSwitch),
            settingRow("Launcher Shortcut", control: shortcutControls)
        ])
        addContent(settings)
        content.setCustomSpacing(12, after: settings)
        addContent(statusLabel)
        addContent(verticalStack([loginStatus, loginSettingsButton], spacing: 8))
    }

    private func settingRow(_ title: String, control: NSView) -> NSView {
        paddedRow(Appearance.stack([
            label(title, size: 13, color: Appearance.text), Appearance.spacer(), control
        ], spacing: 12), height: 38)
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
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            content.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func card(_ rows: [NSView]) -> NSView {
        let surface = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        })
        surface.layer?.cornerRadius = 12
        let stack = verticalStack([], spacing: 0)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = AppearanceSurfaceView(fillColor: .separatorColor)
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                let divider = paddedRow(line, height: 0.5)
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
        menuBarSwitch.state = preferences.showInMenuBar ? .on : .off
        showError(shortcutIsRegistered ? nil : "The shortcut couldn’t be registered. Try a different shortcut.")
        inputSourceSwitch.state = preferences.switchToABC ? .on : .off
        if !shortcutIsRegistered { showSection(.general) }
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
        showError(registered ? nil : "The shortcut couldn’t be registered. Try a different shortcut.")
    }
}
