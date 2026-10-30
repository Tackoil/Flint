import AppKit

@MainActor
final class QuickLinkSettingsView: NSStackView, NSTableViewDataSource, NSTableViewDelegate {
    private let store: QuickLinkStore
    private let table = NSTableView()
    private let emptyLabel = Appearance.label("No quick links yet. Add a place you open often.", size: 13)
    private let editButton = NSButton(title: "Edit…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var links: [QuickLink] = []
    private var editor: QuickLinkEditorController?

    init(store: QuickLinkStore = QuickLinkStore()) {
        self.store = store
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 14
        let description = Appearance.label("Open websites, files, folders, and app links by name from Flint.", size: 13)
        description.maximumNumberOfLines = 2
        description.lineBreakMode = .byWordWrapping
        let add = NSButton(title: "Add Quick Link…", target: self, action: #selector(addLink))
        add.bezelStyle = .rounded
        editButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(editLink)
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteLink)
        let toolbar = Appearance.stack([add, Appearance.spacer(), editButton, deleteButton], spacing: 8)
        for child in [description, makeList(), toolbar] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    private func makeList() -> NSView {
        let column = NSTableColumn(identifier: .init("quickLink"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 54
        table.style = .inset
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(editLink)
        table.setAccessibilityLabel("Quick Links")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.heightAnchor.constraint(equalToConstant: 320).isActive = true
        container.addSubview(scroll)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32)
        ])
        return container
    }

    func reload() {
        let selectedID = selectedLink?.id
        links = store.links
        table.reloadData()
        if let index = links.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        emptyLabel.isHidden = !links.isEmpty
        updateSelection()
    }

    private var selectedLink: QuickLink? {
        links.indices.contains(table.selectedRow) ? links[table.selectedRow] : nil
    }

    private func updateSelection() {
        editButton.isEnabled = selectedLink != nil
        deleteButton.isEnabled = selectedLink != nil
    }

    @objc func addLink() { showEditor(link: nil) }
    @objc private func editLink() {
        guard let selectedLink else { return }
        showEditor(link: selectedLink)
    }

    private func showEditor(link: QuickLink?) {
        guard editor == nil, let window else { return }
        let editor = QuickLinkEditorController(link: link, store: store)
        self.editor = editor
        window.beginSheet(editor.window!) { [weak self] _ in
            self?.editor = nil
            self?.reload()
        }
    }

    @objc private func deleteLink() {
        guard let link = selectedLink, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(link.name)”?"
        alert.informativeText = "This removes the quick link from Flint."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.store.remove(id: link.id)
                self.reload()
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { links.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let link = links[row]
        let name = Appearance.label(link.name, size: 13, weight: .medium, color: .labelColor)
        let destination = Appearance.label(link.link, size: 11)
        destination.lineBreakMode = .byTruncatingMiddle
        destination.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = NSStackView(views: [name, destination])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let row = NSTableCellView()
        labels.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            labels.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            destination.widthAnchor.constraint(equalTo: labels.widthAnchor)
        ])
        row.setAccessibilityLabel("\(link.name), \(link.link)")
        return row
    }
}

private final class QuickLinkEditorPanel: NSPanel {
    #if FLINT_APPEARANCE_CHECKS
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        AppearanceCheckWindows.showsWindows ? super.constrainFrameRect(frameRect, to: screen) : frameRect
    }
    #endif
}

@MainActor
final class QuickLinkEditorController: NSWindowController {
    private let store: QuickLinkStore
    private let id: UUID
    private let nameField = NSTextField()
    private let linkField = NSTextField()
    private let applicationButton = NSButton(title: "Default Application", target: nil, action: nil)
    private let errorLabel = Appearance.label("", size: 12, color: .systemRed)
    private var applicationURL: URL?

    init(link: QuickLink?, store: QuickLinkStore) {
        self.store = store
        id = link?.id ?? UUID()
        applicationURL = link?.applicationURL
        let panel = QuickLinkEditorPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                            styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = link == nil ? "Create Quick Link" : "Edit Quick Link"
        panel.isReleasedWhenClosed = false
        panel.contentView = AppearanceSurfaceView(fillColor: .windowBackgroundColor)
        nameField.stringValue = link?.name ?? ""
        linkField.stringValue = link?.link ?? ""
        configureForm(in: panel)
        panel.initialFirstResponder = nameField
        updateApplicationTitle()
    }

    required init?(coder: NSCoder) { fatalError("Use init(link:store:)") }

    private func configureForm(in panel: NSPanel) {
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        linkField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameField.placeholderString = "e.g. Search Google"
        nameField.setAccessibilityLabel("Quick link name")
        linkField.placeholderString = "https://google.com/search?q={query}"
        linkField.setAccessibilityLabel("Quick link destination")
        applicationButton.bezelStyle = .rounded
        applicationButton.target = self
        applicationButton.action = #selector(chooseApplication)
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetApplication))
        reset.bezelStyle = .rounded
        let application = Appearance.stack([applicationButton, reset, Appearance.spacer()], spacing: 8)
        let hint = Appearance.label("Use {query} for a search term, or named arguments such as {org}/{repo}. URLs, ~/ paths, and app deeplinks are supported.", size: 12)
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.preferredMaxLayoutWidth = 432
        hint.maximumNumberOfLines = 3
        hint.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        let save = NSButton(title: "Save Quick Link", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = .command
        let buttons = Appearance.stack([Appearance.spacer(), cancel, save], spacing: 8)
        let form = NSStackView(views: [fieldRow("Name", field: nameField), fieldRow("Link", field: linkField),
                                      fieldRow("Open With", field: application), hint, errorLabel, buttons])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 16
        form.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(form)
        for child in form.arrangedSubviews { child.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
            form.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24),
            form.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24),
            form.bottomAnchor.constraint(lessThanOrEqualTo: panel.contentView!.bottomAnchor, constant: -24)
        ])
        nameField.nextKeyView = linkField
        linkField.nextKeyView = applicationButton
    }

    private func fieldRow(_ title: String, field: NSView) -> NSView {
        let label = Appearance.label(title, size: 13, color: .labelColor)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        return Appearance.stack([label, field], spacing: 12)
    }

    @objc private func chooseApplication() {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.title = "Choose an Application"
        picker.allowedContentTypes = [.application]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.applicationURL = picker.url
            self?.updateApplicationTitle()
        }
    }

    @objc private func resetApplication() {
        applicationURL = nil
        updateApplicationTitle()
    }

    private func updateApplicationTitle() {
        applicationButton.title = applicationURL?.deletingPathExtension().lastPathComponent ?? "Default Application"
    }

    @objc private func save() {
        do {
            try store.save(QuickLink(id: id, name: nameField.stringValue, link: linkField.stringValue,
                                     applicationURL: applicationURL))
            finish()
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func cancel() { finish() }
    private func finish() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }
}
