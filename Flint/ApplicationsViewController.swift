import AppKit

private final class LauncherResultsScrollView: NSScrollView {
    private let bottomFade = CAGradientLayer()

    override func layout() {
        super.layout()
        wantsLayer = true
        let fadeStart = max(0, 1 - (LauncherLayout.footerHeight + 24) / max(bounds.height, 1))
        let opaque = NSColor.black.cgColor
        let clear = NSColor.clear.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bottomFade.frame = bounds
        bottomFade.startPoint = CGPoint(x: 0.5, y: isFlipped ? 0 : 1)
        bottomFade.endPoint = CGPoint(x: 0.5, y: isFlipped ? 1 : 0)
        bottomFade.colors = [opaque, opaque, clear]
        bottomFade.locations = [0, NSNumber(value: Double(fadeStart)), 1]
        layer?.mask = bottomFade
        CATransaction.commit()
    }
}

@MainActor
final class ApplicationsViewController: NSViewController, NSTextFieldDelegate {
    var onDismiss: (() -> Void)?
    var onPresent: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onSearchExpansionChange: ((Bool) -> Void)?
    private let chrome = LauncherHeaderFooter()
    private let launcherContent = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
    private let resultsContainer = NSStackView()
    private let tableView = NSTableView()
    private let scrollView = LauncherResultsScrollView()
    private let statusLabel = Appearance.label("Finding your applications…", size: 14)
    private let iconCache = NSCache<NSString, NSImage>()
    private var applications: [ApplicationRecord] = []
    private var results: [ApplicationRecord] = []
    private var isLoading = false
    private var isOpening = false
    private var isSearchExpanded = false

    override func loadView() {
        view = Appearance.launcherSurface(content: launcherContent)
        Appearance.setLauncherCornerRadius(LauncherLayout.cornerRadius, on: view)
        launcherContent.wantsLayer = true
        launcherContent.layer?.masksToBounds = true
        configureTable()
        configureLayout()
        chrome.searchField.delegate = self
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
        column.width = 760
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.rowHeight = LauncherLayout.resultRowHeight
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
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets.bottom = LauncherLayout.footerHeight
        scrollView.scrollerInsets.bottom = LauncherLayout.footerHeight
    }

    private func configureLayout() {
        let list = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        list.addSubview(scrollView)
        list.addSubview(statusLabel)
        let footer = chrome.footer()
        footer.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(footer)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: list.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: list.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: list.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: list.widthAnchor, constant: -60),
            footer.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: list.bottomAnchor)
        ])
        let resultViews = [
            Appearance.separator(), list
        ]
        resultViews.forEach { resultsContainer.addArrangedSubview($0) }
        resultsContainer.orientation = .vertical
        resultsContainer.alignment = .width
        resultsContainer.spacing = 0
        resultsContainer.isHidden = true
        resultsContainer.alphaValue = 0
        resultsContainer.translatesAutoresizingMaskIntoConstraints = false
        let searchBar = chrome.searchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        launcherContent.addSubview(searchBar)
        launcherContent.addSubview(resultsContainer)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: launcherContent.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: launcherContent.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: launcherContent.topAnchor),
            resultsContainer.leadingAnchor.constraint(equalTo: launcherContent.leadingAnchor),
            resultsContainer.trailingAnchor.constraint(equalTo: launcherContent.trailingAnchor),
            resultsContainer.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            resultsContainer.heightAnchor.constraint(equalToConstant: 560 - LauncherHeaderFooter.searchBarHeight)
        ])
    }

    @objc func refreshApplications() {
        guard !isLoading else { return }
        isLoading = true
        Task { [weak self] in
            let apps = await Task.detached(priority: .userInitiated) { ApplicationDiscovery.discover() }.value
            guard let self else { return }
            self.applications = apps
            self.isLoading = false
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
        let query = chrome.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = !query.isEmpty
        results = isExpanded ? ApplicationSearch.filter(applications, query: query) : []
        chrome.openButton.isEnabled = !results.isEmpty && !isOpening
        updateEmptyState(hasQuery: isExpanded)
        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        updateSelection()
        updateResultsVisibility(isExpanded)
        onSearchExpansionChange?(isExpanded)
    }

    private func updateResultsVisibility(_ isExpanded: Bool) {
        guard isSearchExpanded != isExpanded else { return }
        isSearchExpanded = isExpanded
        resultsContainer.isHidden = false
        let duration = Appearance.launcherTransitionDuration(for: view.window)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            resultsContainer.animator().alphaValue = isExpanded ? 1 : 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isSearchExpanded == isExpanded else { return }
                self.resultsContainer.isHidden = !isExpanded
            }
        }
    }

    private func updateEmptyState(hasQuery: Bool) {
        statusLabel.isHidden = !results.isEmpty || !hasQuery
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
        onPresent?()
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
        let row = min(max(0, max(0, tableView.selectedRow) + offset), results.count - 1)
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
