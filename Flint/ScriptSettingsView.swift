import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScriptSettingsView: NSStackView, NSTableViewDataSource, NSTableViewDelegate, SettingsKeyboardSection {
    private let store: ScriptCommandStore
    private let folders = NSTableView()
    private let commands = NSTableView()
    private let removeButton = SettingsButton()
    private let revealButton = SettingsButton()
    private let issuesButton = SettingsButton()
    private let addButton = SettingsButton()
    private let createButton = SettingsButton()
    private let refreshButton = SettingsButton()
    private let folderEmpty = Appearance.label("No Script Folders", size: 13)
    private let commandEmpty = Appearance.label("No Scripts", size: 13)
    private let progress = NSProgressIndicator()
    private var directories: [URL] = []
    private(set) var discovery = ScriptDiscovery()
    private(set) var isRefreshing = false
    private var refreshID = UUID()

    init(store: ScriptCommandStore = ScriptCommandStore()) {
        self.store = store
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 20
        configureTable(folders, label: "Script Folders")
        configureTable(commands, label: "Script Commands")
        for child in [makeFolderList(), makeCommandList()] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    private func configureTable(_ table: NSTableView, label: String) {
        table.addTableColumn(NSTableColumn(identifier: .init(label)))
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
        table.setAccessibilityLabel(label)
    }

    private func makeFolderList() -> NSView {
        let add = addButton
        configureIcon(add, symbol: "plus", title: "Add Folder…", action: #selector(addFolder))
        configureIcon(removeButton, symbol: "minus", title: "Remove Script Folder", action: #selector(removeFolder))
        removeButton.toolTip = "Remove the selected folder from Flint. Its files are kept."
        configureIcon(revealButton, symbol: "folder", title: "Show Folder in Finder", action: #selector(revealFolder))
        let toolbar = Appearance.stack([add, toolbarDivider(), removeButton, Appearance.spacer(), revealButton], spacing: 4)
        return makeList(title: "Script Folders", table: folders, empty: folderEmpty, height: 80,
                        accessories: [], toolbar: toolbar)
    }

    private func makeCommandList() -> NSView {
        let create = createButton
        configureIcon(create, symbol: "plus", title: "Create Script…", action: #selector(createScript))
        let refresh = refreshButton
        configureIcon(refresh, symbol: "arrow.clockwise", title: "Refresh Scripts", action: #selector(refreshScripts))
        configureIcon(issuesButton, symbol: "exclamationmark.triangle", title: "Script Issues", action: #selector(showIssues))
        issuesButton.isHidden = true
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        let toolbar = Appearance.stack([create, Appearance.spacer(), refresh], spacing: 4)
        return makeList(title: "Commands", table: commands, empty: commandEmpty, height: 160,
                        accessories: [progress, issuesButton], toolbar: toolbar)
    }

    private func makeList(title: String, table: NSTableView, empty: NSTextField, height: CGFloat,
                          accessories: [NSView], toolbar: NSView) -> NSView {
        let surface = AppearanceSurfaceView(fillColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        })
        surface.layer?.cornerRadius = 12
        surface.layer?.masksToBounds = true
        let heading = Appearance.stack([Appearance.label(title, size: 13, weight: .semibold, color: .labelColor),
                                       Appearance.spacer()] + accessories, spacing: 8)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let topDivider = AppearanceSurfaceView(fillColor: .separatorColor)
        let bottomDivider = AppearanceSurfaceView(fillColor: .separatorColor)
        for child in [heading, topDivider, scroll, bottomDivider, toolbar, empty] {
            child.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            heading.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            heading.topAnchor.constraint(equalTo: surface.topAnchor),
            heading.heightAnchor.constraint(equalToConstant: 38),
            topDivider.topAnchor.constraint(equalTo: heading.bottomAnchor),
            scroll.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: height),
            bottomDivider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: bottomDivider.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 6),
            toolbar.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            toolbar.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        for divider in [topDivider, bottomDivider] {
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
                divider.heightAnchor.constraint(equalToConstant: 0.5)
            ])
        }
        return surface
    }

    private func toolbarDivider() -> NSView {
        let divider = AppearanceSurfaceView(fillColor: .separatorColor)
        divider.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return divider
    }

    private func button(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = SettingsButton()
        configureIcon(button, symbol: symbol, title: title, action: action)
        return button
    }

    private func configureIcon(_ button: NSButton, symbol: String, title: String, action: Selector) {
        Appearance.configureSettingsButton(button, symbol: symbol, title: title)
        button.target = self
        button.action = action
    }

    func reload() {
        let selected = selectedDirectory
        directories = store.directories
        folders.reloadData()
        if let index = directories.firstIndex(where: { $0 == selected }) {
            folders.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        folderEmpty.isHidden = !directories.isEmpty
        updateFolderControls()
        refreshScripts()
    }

    private var selectedDirectory: URL? {
        directories.indices.contains(folders.selectedRow) ? directories[folders.selectedRow] : nil
    }

    var keyboardControls: [NSView] { [folders, addButton, removeButton, revealButton, commands, createButton, refreshButton, issuesButton] }
    var keyboardNavigationControls: [NSView] { [folders, commands] }

    var keyboardActions: [SettingsAction] {
        [SettingsAction(button: addButton, title: "Add Folder…", key: "n"),
         SettingsAction(button: createButton, title: "Create Script…", key: "n", modifiers: [.command, .shift]),
         SettingsAction("Edit Script", key: "e", isEnabled: discovery.commands.indices.contains(commands.selectedRow)) { [weak self] in
             self?.editSelectedScript()
         },
         SettingsAction(button: removeButton, title: "Remove Script Folder", key: "\u{7f}"),
         SettingsAction(button: revealButton, title: "Show Folder in Finder", key: "o"),
         SettingsAction(button: refreshButton, title: "Refresh Scripts", key: "r"),
         SettingsAction(button: issuesButton, title: issuesButton.accessibilityLabel() ?? "Script Issues", key: "i")]
    }

    func keyboardPrimaryAction(for control: NSView?) -> SettingsAction? {
        if control === folders {
            let action = keyboardActions[4]
            return SettingsAction("Open", isEnabled: action.isEnabled, perform: action.perform)
        }
        if control === commands {
            let action = keyboardActions[2]
            return SettingsAction("Edit", isEnabled: action.isEnabled, perform: action.perform)
        }
        return nil
    }

    private func editSelectedScript() {
        let sender = NSButton()
        sender.tag = commands.selectedRow
        editScript(sender)
    }

    private func updateFolderControls() {
        removeButton.isEnabled = selectedDirectory != nil
        revealButton.isEnabled = selectedDirectory != nil
    }

    @objc private func refreshScripts() {
        let id = UUID()
        refreshID = id
        let directories = directories
        isRefreshing = true
        progress.startAnimation(nil)
        commandEmpty.isHidden = true
        NotificationCenter.default.post(name: ScriptCommandStore.didChange, object: store)
        Task { [weak self] in
            let result = await Task.detached { ScriptDiscovery.scan(directories: directories) }.value
            guard let self, refreshID == id else { return }
            discovery = result
            isRefreshing = false
            progress.stopAnimation(nil)
            commands.reloadData()
            commandEmpty.isHidden = !result.commands.isEmpty
            let issueTitle = result.issues.count == 1 ? "1 Issue…" : "\(result.issues.count) Issues…"
            issuesButton.toolTip = issueTitle
            issuesButton.setAccessibilityLabel(issueTitle)
            issuesButton.isHidden = result.issues.isEmpty
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === folders ? directories.count : discovery.commands.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ApplicationRow() }

    func tableViewSelectionDidChange(_ notification: Notification) { updateFolderControls() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === folders {
            guard directories.indices.contains(row) else { return nil }
            let url = directories[row]
            return makeRow(symbol: "folder", title: (url.path as NSString).abbreviatingWithTildeInPath, path: url.path)
        }
        guard discovery.commands.indices.contains(row) else { return nil }
        let command = discovery.commands[row]
        let edit = button("Edit", symbol: "pencil", action: #selector(editScript(_:)))
        edit.tag = row
        edit.setAccessibilityLabel("Edit \(command.name)")
        edit.toolTip = "Edit \(command.url.lastPathComponent)"
        return makeRow(symbol: "terminal", title: command.name, path: command.url.path, action: edit)
    }

    private func makeRow(symbol: String, title: String, path: String, action: NSView? = nil) -> NSView {
        let cell = NSTableCellView()
        let name = Appearance.label(title, size: 13, color: .labelColor)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let icon = Appearance.symbol(symbol, size: 16, color: .secondaryLabelColor)
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let content = Appearance.stack([icon, name, Appearance.spacer()] + (action.map { [$0] } ?? []), spacing: 10)
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(content)
        cell.textField = name
        cell.toolTip = path
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func addFolder() {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.title = "Add Script Folder"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = true
        picker.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            picker.urls.forEach { self.store.add($0) }
            reload()
        }
    }

    @objc private func removeFolder() {
        guard let selectedDirectory else { return }
        store.remove(selectedDirectory)
        reload()
    }

    @objc private func revealFolder() {
        guard let selectedDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedDirectory])
    }

    @objc private func editScript(_ sender: NSButton) {
        guard discovery.commands.indices.contains(sender.tag), let window else { return }
        let url = discovery.commands[sender.tag].url
        guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: .init()) { _, error in
            guard let error else { return }
            Task { @MainActor in NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    @objc private func showIssues() {
        guard let window, !discovery.issues.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Some Scripts Couldn’t Be Loaded"
        let details = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        details.isEditable = false
        details.isRichText = false
        details.drawsBackground = false
        details.textColor = .labelColor
        details.font = .systemFont(ofSize: 12)
        details.isVerticallyResizable = true
        details.autoresizingMask = [.width]
        details.textContainer?.widthTracksTextView = true
        details.string = discovery.issues.joined(separator: "\n\n")
        details.setAccessibilityLabel("Script loading issues")
        let scroll = NSScrollView(frame: details.frame)
        scroll.documentView = details
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        alert.accessoryView = scroll
        alert.beginSheetModal(for: window)
    }

    @objc func createScript() {
        guard let window else { return }
        let picker = NSSavePanel()
        picker.title = "Create Script Command"
        picker.nameFieldStringValue = "hello-world.sh"
        picker.allowedContentTypes = [.shellScript]
        picker.directoryURL = selectedDirectory ?? directories.first
        picker.canCreateDirectories = true
        picker.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = picker.url else { return }
            do {
                try ScriptCommandStore.template.write(to: url, atomically: true, encoding: .utf8)
                store.add(url.deletingLastPathComponent())
                reload()
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
}
