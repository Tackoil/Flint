import AppKit

@MainActor
final class TranslationSettingsView: NSStackView, NSTableViewDataSource, NSTableViewDelegate {
    private let preferences: TranslationPreferences
    private let hasAPIKey: () throws -> Bool
    private let saveAPIKey: (String) throws -> Void
    private let deleteAPIKey: () throws -> Void
    private let keyField = NSSecureTextField()
    private let languages = NSTableView()
    private let addLanguageButton = NSButton()
    private let removeLanguageButton = NSButton()
    private var isReloadingLanguages = false
    private let errorLabel = Appearance.label("", size: 12, color: .systemRed)
    private let saveButton = NSButton(title: "Save Key", target: nil, action: nil)
    private let removeButton = NSButton()
    private let savedKey = Appearance.label("••••••••••••", size: 13, color: .labelColor)
    private let nativeNames: [TranslationLanguage: String] = [
        .simplifiedChinese: "简体中文", .traditionalChinese: "繁體中文", .english: "English",
        .japanese: "日本語", .korean: "한국어", .french: "Français", .german: "Deutsch",
        .spanish: "Español", .portuguese: "Português", .italian: "Italiano", .russian: "Русский",
        .arabic: "العربية", .hindi: "हिन्दी", .vietnamese: "Tiếng Việt", .thai: "ไทย"
    ]

    init(preferences: TranslationPreferences = TranslationPreferences(),
         hasAPIKey: @escaping () throws -> Bool = { try TranslationAPIKeyStore().containsKey() },
         saveAPIKey: @escaping (String) throws -> Void = { try TranslationAPIKeyStore().save($0) },
         deleteAPIKey: @escaping () throws -> Void = { try TranslationAPIKeyStore().delete() }) {
        self.preferences = preferences
        self.hasAPIKey = hasAPIKey
        self.saveAPIKey = saveAPIKey
        self.deleteAPIKey = deleteAPIKey
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 20
        configureKeyControls()
        errorLabel.maximumNumberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.isHidden = true
        for child in [makeLanguageList(), makeKeyRow(), errorLabel] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        refreshKeyStatus()
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func configureKeyControls() {
        keyField.placeholderString = "Paste API key"
        keyField.alignment = .right
        keyField.setAccessibilityLabel("DeepSeek API key")
        keyField.target = self
        keyField.action = #selector(saveKey)
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        savedKey.alignment = .right
        savedKey.setAccessibilityLabel("DeepSeek API key saved")
        savedKey.isHidden = true
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveKey)
        removeButton.title = ""
        removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove API key")
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.toolTip = "Remove API key"
        removeButton.setAccessibilityLabel("Remove API key")
        removeButton.target = self
        removeButton.action = #selector(removeKey)
        removeButton.isHidden = true
        removeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        removeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func makeSurface() -> NSView {
        let surface = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        })
        surface.layer?.cornerRadius = 12
        surface.layer?.masksToBounds = true
        return surface
    }

    private func makeKeyRow() -> NSView {
        let surface = makeSurface()
        let title = Appearance.label("DeepSeek API Key", size: 13, color: .labelColor)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        let controls = Appearance.stack([title, Appearance.spacer(), keyField, savedKey, saveButton, removeButton], spacing: 8)
        controls.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(controls)
        NSLayoutConstraint.activate([
            surface.heightAnchor.constraint(equalToConstant: 46),
            controls.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            keyField.widthAnchor.constraint(equalToConstant: 190)
        ])
        return surface
    }

    private func makeLanguageList() -> NSView {
        let surface = makeSurface()
        let heading = Appearance.label("Translate to", size: 13, weight: .semibold, color: .labelColor)
        let divider = AppearanceSurfaceView(fillColor: .separatorColor)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        configureLanguageTable()
        scroll.documentView = languages
        let toolbar = makeLanguageToolbar()
        let footerDivider = AppearanceSurfaceView(fillColor: .separatorColor)
        for child in [heading, divider, scroll, footerDivider, toolbar] {
            child.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            heading.topAnchor.constraint(equalTo: surface.topAnchor, constant: 12),
            heading.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            divider.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 104),
            footerDivider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footerDivider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            footerDivider.heightAnchor.constraint(equalToConstant: 0.5),
            toolbar.topAnchor.constraint(equalTo: footerDivider.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 6),
            toolbar.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -6),
            toolbar.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 28)
        ])
        return surface
    }

    private func makeLanguageToolbar() -> NSView {
        for (button, symbol, title, action) in [
            (addLanguageButton, "plus", "Add language", #selector(showLanguageMenu)),
            (removeLanguageButton, "minus", "Remove language", #selector(removeLanguage))
        ] {
            button.title = ""
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.isBordered = false
            button.setAccessibilityLabel(title)
            button.toolTip = title
            button.target = self
            button.action = action
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        updateLanguageControls()
        let divider = AppearanceSurfaceView(fillColor: .separatorColor)
        divider.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return Appearance.stack([addLanguageButton, divider, removeLanguageButton, Appearance.spacer()], spacing: 0)
    }

    private func updateLanguageControls() {
        let menu = NSMenu(title: "Add language")
        for language in TranslationLanguage.allCases where !preferences.targetLanguages.contains(language) {
            let title = "\(nativeNames[language] ?? language.rawValue) — \(language.rawValue)"
            let item = NSMenuItem(title: title, action: #selector(addLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.rawValue
            item.target = self
            menu.addItem(item)
        }
        addLanguageButton.menu = menu
        addLanguageButton.isEnabled = !menu.items.isEmpty
        removeLanguageButton.isEnabled = preferences.targetLanguages.count > 1 && languages.selectedRow >= 0
    }

    @objc private func showLanguageMenu() {
        addLanguageButton.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: addLanguageButton)
    }

    @objc private func addLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let language = TranslationLanguage(rawValue: value),
              !preferences.targetLanguages.contains(language) else { return }
        preferences.targetLanguages.append(language)
        preferences.targetLanguage = language
        reloadLanguages()
    }

    @objc private func removeLanguage() {
        var saved = preferences.targetLanguages
        guard saved.count > 1, saved.indices.contains(languages.selectedRow) else { return }
        saved.remove(at: languages.selectedRow)
        preferences.targetLanguages = saved
        reloadLanguages()
    }

    private func reloadLanguages() {
        let selected = preferences.targetLanguages.firstIndex(of: preferences.targetLanguage) ?? 0
        isReloadingLanguages = true
        languages.reloadData()
        languages.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        languages.scrollRowToVisible(selected)
        isReloadingLanguages = false
        updateLanguageControls()
    }

    private func configureLanguageTable() {
        for identifier in ["native", "english"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.width = 220
            column.minWidth = 100
            languages.addTableColumn(column)
        }
        languages.headerView = nil
        languages.style = .fullWidth
        languages.rowHeight = 26
        languages.intercellSpacing = NSSize(width: 12, height: 0)
        languages.backgroundColor = .clear
        languages.allowsEmptySelection = false
        languages.allowsMultipleSelection = false
        languages.allowsColumnReordering = false
        languages.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        languages.setAccessibilityLabel("Translation target language")
        languages.dataSource = self
        languages.delegate = self
        reloadLanguages()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { preferences.targetLanguages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isNative = tableColumn?.identifier.rawValue == "native"
        let language = preferences.targetLanguages[row]
        let title = isNative ? nativeNames[language] ?? language.rawValue : language.rawValue
        let cell = NSTableCellView()
        let label = Appearance.label(title, size: 13, color: isNative ? .labelColor : .secondaryLabelColor)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloadingLanguages, preferences.targetLanguages.indices.contains(languages.selectedRow) else { return }
        preferences.targetLanguage = preferences.targetLanguages[languages.selectedRow]
        updateLanguageControls()
    }

    @objc private func saveKey() {
        do {
            try saveAPIKey(keyField.stringValue)
            keyField.stringValue = ""
            refreshKeyStatus()
        } catch { showError(error) }
    }

    @objc private func removeKey() {
        do {
            try deleteAPIKey()
            keyField.stringValue = ""
            refreshKeyStatus()
        } catch { showError(error) }
    }

    private func refreshKeyStatus() {
        do {
            let hasKey = try hasAPIKey()
            keyField.isHidden = hasKey
            saveButton.isHidden = hasKey
            savedKey.isHidden = !hasKey
            removeButton.isHidden = !hasKey
            errorLabel.isHidden = true
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        errorLabel.stringValue = error.localizedDescription
        errorLabel.isHidden = false
    }
}
