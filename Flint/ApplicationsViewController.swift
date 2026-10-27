import AppKit

@MainActor
final class ApplicationsViewController: NSViewController, NSTextFieldDelegate {
    var onDismiss: (() -> Void)?
    var onShowSettings: (() -> Void)?
    private let chrome = LauncherHeaderFooter()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = Appearance.label("Finding your applications…", size: 14)
    private let iconCache = NSCache<NSString, NSImage>()
    private var applications: [ApplicationRecord] = []
    private var results: [ApplicationRecord] = []
    private var isLoading = false
    private var isOpening = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
        view.wantsLayer = true
        view.layer?.backgroundColor = Appearance.background.cgColor
        view.layer?.cornerRadius = 16
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        view.layer?.masksToBounds = true
        configureTable()
        configureLayout()
        chrome.searchField.delegate = self
        chrome.refreshButton.target = self
        chrome.refreshButton.action = #selector(refreshApplications)
        chrome.dismissButton.target = self
        chrome.dismissButton.action = #selector(dismissLauncher)
        chrome.openButton.target = self
        chrome.openButton.action = #selector(openSelectedApplication)
        chrome.openButton.isEnabled = false
        chrome.settingsButton.target = self
        chrome.settingsButton.action = #selector(showSettings)
        refreshApplications()
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: ApplicationRowContent.identifier)
        column.resizingMask = .autoresizingMask
        column.width = 734
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.rowHeight = 54
        tableView.intercellSpacing = .zero
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(openClickedApplication)
        tableView.setAccessibilityLabel("Applications")
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
    }

    private func configureLayout() {
        let list = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        list.addSubview(scrollView)
        list.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 13),
            scrollView.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -13),
            scrollView.topAnchor.constraint(equalTo: list.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: list.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: list.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: list.widthAnchor, constant: -60)
        ])
        let stack = NSStackView(views: [
            chrome.searchBar(), Appearance.separator(), chrome.sectionBar(), list,
            chrome.selectionBar(), Appearance.separator(), chrome.footer()
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc func refreshApplications() {
        guard !isLoading else { return }
        isLoading = true
        chrome.refreshButton.isEnabled = false
        Task { [weak self] in
            let apps = await Task.detached(priority: .userInitiated) { ApplicationDiscovery.discover() }.value
            guard let self else { return }
            self.applications = apps
            self.isLoading = false
            self.chrome.refreshButton.isEnabled = true
            self.iconCache.removeAllObjects()
            self.applyQuery()
        }
    }

    func resetSearch() {
        _ = view
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    func controlTextDidChange(_ obj: Notification) { applyQuery() }

    private func applyQuery() {
        results = ApplicationSearch.filter(applications, query: chrome.searchField.stringValue)
        chrome.countLabel.stringValue = "\(results.count)"
        chrome.openButton.isEnabled = !results.isEmpty && !isOpening
        updateEmptyState()
        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        updateSelection()
    }

    private func updateEmptyState() {
        statusLabel.isHidden = !results.isEmpty
        if isLoading {
            statusLabel.stringValue = "Finding your applications…"
        } else if applications.isEmpty {
            statusLabel.stringValue = "No applications available\nInstall an app in Applications, then refresh."
        } else {
            statusLabel.stringValue = "No applications found\nTry a different name."
        }
    }

    private func updateSelection() {
        let row = tableView.selectedRow
        chrome.pathLabel.stringValue = results.indices.contains(row) ? results[row].url.path : ""
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.location != NSNotFound else { return }
        for index in visible.location..<NSMaxRange(visible) {
            let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? ApplicationRowContent
            cell?.updateSelection(index == row)
        }
    }

    @objc private func openClickedApplication() {
        guard tableView.clickedRow >= 0 else { return }
        openSelectedApplication()
    }

    @objc private func openSelectedApplication() {
        let row = tableView.selectedRow
        guard !isOpening, results.indices.contains(row) else { return }
        let app = results[row]
        isOpening = true
        chrome.openButton.isEnabled = false
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async { self?.finishOpening(app, error: error) }
        }
    }

    private func finishOpening(_ app: ApplicationRecord, error: Error?) {
        isOpening = false
        chrome.openButton.isEnabled = !results.isEmpty
        guard let error else {
            onDismiss?()
            return
        }
        guard let window = view.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "Couldn’t open \(app.name)"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    @objc private func dismissLauncher() { onDismiss?() }
    @objc private func showSettings() { onShowSettings?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let actions: [Selector: () -> Void] = [
            #selector(NSResponder.moveDown(_:)): { self.moveSelection(by: 1) },
            #selector(NSResponder.moveUp(_:)): { self.moveSelection(by: -1) },
            #selector(NSResponder.insertNewline(_:)): openSelectedApplication,
            #selector(NSResponder.cancelOperation(_:)): dismissLauncher
        ]
        guard let action = actions[commandSelector] else { return false }
        action()
        return true
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let row = (max(0, tableView.selectedRow) + offset + results.count) % results.count
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        updateSelection()
    }
}

extension ApplicationsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ApplicationRow() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ApplicationRowContent.identifier, owner: self) as? ApplicationRowContent
            ?? ApplicationRowContent(frame: .zero)
        let app = results[row]
        cell.configure(application: app, icon: icon(for: app), selected: row == tableView.selectedRow)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }

    private func icon(for app: ApplicationRecord) -> NSImage {
        if let image = iconCache.object(forKey: app.id as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: 64, height: 64)
        iconCache.setObject(image, forKey: app.id as NSString)
        return image
    }
}
