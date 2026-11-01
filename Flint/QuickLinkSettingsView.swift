import AppKit

@MainActor
final class QuickLinkSettingsView: NSStackView, NSTableViewDataSource, NSTableViewDelegate {
    private let store: QuickLinkStore
    private let table = NSTableView()
    private let emptyLabel = Appearance.label("No quick links yet. Add a place you open often.", size: 13)
    private var links: [QuickLink] = []
    private var editor: QuickLinkEditorController?

    init(store: QuickLinkStore = QuickLinkStore()) {
        self.store = store
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 14
        let add = NSButton(title: "Add Quick Link…", target: self, action: #selector(addLink))
        add.bezelStyle = .rounded
        let toolbar = Appearance.stack([Appearance.spacer(), add], spacing: 8)
        for child in [makeList(), toolbar] {
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
        table.style = .fullWidth
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(editLink)
        table.doubleAction = #selector(editLink)
        table.setAccessibilityLabel("Quick Links")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let container = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        })
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
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
    }

    private var selectedLink: QuickLink? {
        links.indices.contains(table.selectedRow) ? links[table.selectedRow] : nil
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

    private func removeLink(id: UUID) {
        do {
            try store.remove(id: id)
            reload()
        } catch {
            guard let window else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { links.count }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int,
                   edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing, links.indices.contains(row) else { return [] }
        let id = links[row].id
        return [NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self, weak tableView] _, _ in
            tableView?.rowActionsVisible = false
            self?.removeLink(id: id)
        }]
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        QuickLinkSettingsCell(link: links[row], showsDivider: row < links.count - 1)
    }
}

@MainActor
private final class QuickLinkSettingsCell: NSTableCellView {
    init(link: QuickLink, showsDivider: Bool) {
        super.init(frame: .zero)
        let icon = NSImageView(image: Self.icon(for: link))
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        let name = Appearance.label(link.name, size: 13, weight: .medium, color: .labelColor)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let destination = Appearance.label(link.link, size: 12)
        destination.lineBreakMode = .byTruncatingMiddle
        destination.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let content = Appearance.stack([icon, name, Appearance.spacer(), destination], spacing: 10)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        textField = name
        imageView = icon
        toolTip = "\(link.name) — \(link.link)"
        setAccessibilityLabel("\(link.name), \(link.link)")
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            destination.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.42)
        ])
        if showsDivider { addDivider() }
    }

    required init?(coder: NSCoder) { fatalError("Use init(link:showsDivider:)") }

    private static func icon(for link: QuickLink) -> NSImage {
        if let url = try? link.resolvedURL(), url.isFileURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let application = link.applicationURL { return NSWorkspace.shared.icon(forFile: application.path) }
        return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
    }

    private func addDivider() {
        let divider = AppearanceSurfaceView(fillColor: .separatorColor)
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5)
        ])
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
