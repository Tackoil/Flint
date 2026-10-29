import AppKit

@MainActor
final class TranslationSettingsView: NSStackView {
    private let preferences = TranslationPreferences()
    private let keyStore = TranslationAPIKeyStore()
    private let keyField = NSSecureTextField()
    private let language = NSPopUpButton()
    private let status = Appearance.label("", size: 12)
    private let removeButton = NSButton(title: "Remove Key", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 14
        language.addItems(withTitles: TranslationLanguage.allCases.map(\.rawValue))
        language.selectItem(withTitle: preferences.targetLanguage.rawValue)
        language.target = self
        language.action = #selector(changeLanguage)
        language.setAccessibilityLabel("Translation target language")
        keyField.placeholderString = "Paste your DeepSeek API key"
        keyField.setAccessibilityLabel("DeepSeek API key")
        let save = NSButton(title: "Save Key", target: self, action: #selector(saveKey))
        save.bezelStyle = .rounded
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeKey)
        let keyButtons = Appearance.stack([save, removeButton], spacing: 8)
        let usage = Appearance.label("Find the Translate action, press Tab, then enter your text. Translation starts after a 600 ms pause. Press Return to copy the result.", size: 12)
        let privacy = Appearance.label("Your key is stored in macOS Keychain. Text entered in translation mode is sent to DeepSeek automatically after you pause typing. Translations aren’t saved by Flint.", size: 12)
        let getKey = NSButton(title: "Get a DeepSeek API Key…", target: self, action: #selector(openPlatform))
        getKey.bezelStyle = .rounded
        for label in [usage, privacy, status] {
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.cell?.usesSingleLineMode = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.preferredMaxLayoutWidth = 460
        }
        for child in [Appearance.label("Translate to", size: 13, weight: .medium, color: .labelColor), language,
                      Appearance.label("DeepSeek API Key", size: 13, weight: .medium, color: .labelColor),
                      keyField, keyButtons, status, usage, privacy, getKey] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        refreshKeyStatus()
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    @objc private func changeLanguage() {
        guard let title = language.titleOfSelectedItem, let selected = TranslationLanguage(rawValue: title) else { return }
        preferences.targetLanguage = selected
    }

    @objc private func saveKey() {
        do {
            try keyStore.save(keyField.stringValue)
            keyField.stringValue = ""
            refreshKeyStatus()
        } catch { showStatus(error.localizedDescription, isError: true) }
    }

    @objc private func removeKey() {
        do {
            try keyStore.delete()
            keyField.stringValue = ""
            refreshKeyStatus()
        } catch { showStatus(error.localizedDescription, isError: true) }
    }

    private func refreshKeyStatus() {
        do {
            let hasKey = try keyStore.read()?.isEmpty == false
            removeButton.isEnabled = hasKey
            showStatus(hasKey ? "API key saved in Keychain." : "Add an API key to enable translation.", isError: false)
        } catch { showStatus(error.localizedDescription, isError: true) }
    }

    private func showStatus(_ message: String, isError: Bool) {
        status.stringValue = message
        status.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    @objc private func openPlatform() {
        NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/api_keys")!)
    }
}
