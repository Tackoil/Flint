import AppKit

@MainActor
final class QuickLinkSettingsView: NSStackView, NSTableViewDataSource, NSTableViewDelegate {
    private let store: QuickLinkStore
    private let table = NSTableView()
    private let removeButton = NSButton()
    private let emptyLabel = Appearance.label("No Quick Links", size: 13)
    private var links: [QuickLink] = []
    private var editor: QuickLinkEditorController?

    init(store: QuickLinkStore = QuickLinkStore()) {
        self.store = store
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 20
        let list = makeList()
        addArrangedSubview(list)
        list.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        reload()
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    private func makeList() -> NSView {
        let column = NSTableColumn(identifier: .init("quickLink"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 40
        table.style = .fullWidth
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("Quick Links")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let container = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        })
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        let heading = Appearance.stack([
            Appearance.label("Links", size: 13, weight: .semibold, color: .labelColor), Appearance.spacer()
        ], spacing: 8)
        let topDivider = AppearanceSurfaceView(fillColor: .separatorColor)
        let bottomDivider = AppearanceSurfaceView(fillColor: .separatorColor)
        let toolbar = makeToolbar()
        for child in [heading, topDivider, scroll, bottomDivider, toolbar, emptyLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            heading.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            heading.topAnchor.constraint(equalTo: container.topAnchor),
            heading.heightAnchor.constraint(equalToConstant: 38),
            topDivider.topAnchor.constraint(equalTo: heading.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 320),
            bottomDivider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: bottomDivider.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            toolbar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        for divider in [topDivider, bottomDivider] {
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                divider.heightAnchor.constraint(equalToConstant: 0.5)
            ])
        }
        return container
    }

    private func makeToolbar() -> NSView {
        let add = NSButton(title: "Add Quick Link…", target: self, action: #selector(addLink))
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        add.isBordered = false
        add.font = .systemFont(ofSize: 12)
        add.setAccessibilityLabel("Add Quick Link…")
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove Quick Link")
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.toolTip = "Remove the selected quick link."
        removeButton.setAccessibilityLabel("Remove Quick Link")
        removeButton.target = self
        removeButton.action = #selector(removeSelectedLink)
        removeButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        let divider = AppearanceSurfaceView(fillColor: .separatorColor)
        divider.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return Appearance.stack([add, divider, removeButton, Appearance.spacer()], spacing: 4)
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

    @objc func addLink() { showEditor(link: nil) }
    @objc private func editLink(_ sender: NSButton) {
        guard links.indices.contains(sender.tag) else { return }
        showEditor(link: links[sender.tag])
    }

    @objc private func removeSelectedLink() {
        guard let selectedLink else { return }
        removeLink(id: selectedLink.id)
    }

    private func updateSelection() { removeButton.isEnabled = selectedLink != nil }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }

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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let link = links[row]
        let edit = NSButton(title: "Edit", target: self, action: #selector(editLink(_:)))
        edit.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        edit.imagePosition = .imageLeading
        edit.isBordered = false
        edit.font = .systemFont(ofSize: 12)
        edit.tag = row
        edit.setAccessibilityLabel("Edit \(link.name)")
        edit.toolTip = "Edit \(link.name)"
        return QuickLinkSettingsCell(link: link, edit: edit)
    }
}

@MainActor
private final class QuickLinkSettingsCell: NSTableCellView {
    init(link: QuickLink, edit: NSButton) {
        super.init(frame: .zero)
        let icon = NSImageView(image: Self.icon(for: link))
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        let name = Appearance.label(link.name, size: 13, color: .labelColor)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let content = Appearance.stack([icon, name, Appearance.spacer(), edit], spacing: 10)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        textField = name
        imageView = icon
        toolTip = "\(link.name) — \(link.link)"
        setAccessibilityLabel("\(link.name), \(link.link)")
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(link:edit:)") }

    private static func icon(for link: QuickLink) -> NSImage {
        if let url = try? link.resolvedURL(), url.isFileURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let application = link.applicationURL { return NSWorkspace.shared.icon(forFile: application.path) }
        return NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) ?? NSImage()
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
    private let resetButton = NSButton()
    private let errorLabel = Appearance.label("", size: 12, color: .systemRed)
    private let form = NSStackView()
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
        let application = makeApplicationControl()
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.preferredMaxLayoutWidth = 432
        errorLabel.isHidden = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        let save = NSButton(title: "Save Quick Link", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = .command
        let buttons = Appearance.stack([Appearance.spacer(), cancel, save], spacing: 8)
        for child in [fieldRow("Name", field: nameField), fieldRow("Link", field: linkField),
                      fieldRow("Open With", field: application), errorLabel, buttons] {
            form.addArrangedSubview(child)
        }
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 16
        form.detachesHiddenViews = true
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

    private func makeApplicationControl() -> NSView {
        applicationButton.bezelStyle = .rounded
        applicationButton.alignment = .left
        applicationButton.imagePosition = .imageLeading
        applicationButton.imageHugsTitle = true
        applicationButton.imageScaling = .scaleProportionallyDown
        applicationButton.cell?.lineBreakMode = .byTruncatingTail
        applicationButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        applicationButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applicationButton.setAccessibilityLabel("Open With")
        applicationButton.target = self
        applicationButton.action = #selector(chooseApplication)
        resetButton.title = ""
        resetButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        resetButton.imagePosition = .imageOnly
        resetButton.bezelStyle = .rounded
        resetButton.showsBorderOnlyWhileMouseInside = true
        resetButton.controlSize = .small
        resetButton.toolTip = "Reset to Default Application"
        resetButton.setAccessibilityLabel("Reset Open With")
        resetButton.target = self
        resetButton.action = #selector(resetApplication)
        resetButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        resetButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let control = Appearance.stack([applicationButton, resetButton], spacing: 8)
        control.distribution = .fill
        return control
    }

    private func fitContent() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 480, height: ceil(form.fittingSize.height) + 48))
        content.layoutSubtreeIfNeeded()
    }

    private func fieldRow(_ title: String, field: NSView) -> NSView {
        let label = Appearance.label(title, size: 13, color: .labelColor)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let row = Appearance.stack([label, field], spacing: 12)
        field.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        return row
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
        let icon: NSImage?
        if let applicationURL {
            icon = NSWorkspace.shared.icon(forFile: applicationURL.path).copy() as? NSImage
        } else {
            icon = Self.defaultApplicationIcon()
        }
        icon?.size = NSSize(width: 16, height: 16)
        icon?.alignmentRect = NSRect(x: 0, y: 0, width: 16, height: 16)
        applicationButton.image = icon
        applicationButton.toolTip = applicationURL?.path ?? "Use the system’s default application"
        resetButton.isEnabled = applicationURL != nil
        fitContent()
    }

    private static func defaultApplicationIcon() -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "app", accessibilityDescription: nil) else { return nil }
        // Symbol images have special button metrics. Use a regular template image
        // so the placeholder shares the same icon slot as application artwork.
        let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        icon.isTemplate = true
        return icon
    }

    @objc private func save() {
        do {
            try store.save(QuickLink(id: id, name: nameField.stringValue, link: linkField.stringValue,
                                     applicationURL: applicationURL))
            finish()
        } catch {
            errorLabel.stringValue = error.localizedDescription
            errorLabel.isHidden = false
            fitContent()
        }
    }

    @objc private func cancel() { finish() }
    private func finish() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }
}
