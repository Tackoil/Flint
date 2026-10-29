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
    var onShowSettings: (() -> Void)?
    var onDisplayModeChange: ((LauncherDisplayMode) -> Void)?
    private let chrome = LauncherHeaderFooter()
    private let launcherContent = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
    private let resultsContainer = NSStackView()
    private var footerView: NSView?
    private lazy var resultsHeightConstraint = resultsContainer.heightAnchor.constraint(
        equalToConstant: LauncherDisplayMode.results.height - LauncherHeaderFooter.searchBarHeight)
    private let tableView = NSTableView()
    private let scrollView = LauncherResultsScrollView()
    private let calculatorView = CalculatorResultView()
    private var calculation: CalculatorResult?
    private var isRoundingEnabled = true
    private var timestampOutputUnit = TimestampCalculation.Unit.seconds
    private let statusLabel = Appearance.label("Finding your applications…", size: 14)
    private let iconCache = NSCache<NSString, NSImage>()
    private var applications: [ApplicationRecord] = []
    private var results: [LauncherItem] = []
    private let actionExecutor = SystemActionExecutor()
    private let errorNotifier = LauncherErrorNotifier()
    private var isLoading = false
    private var isOpening = false
    private var isSearchExpanded = false
    private var dialog: LauncherDialogView?
    var isPresentingDialog: Bool { dialog != nil }
    var displayMode: LauncherDisplayMode {
        if isPresentingDialog { return .results }
        if calculation != nil { return .calculator }
        return isSearchExpanded ? .results : .collapsed
    }

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
        chrome.roundingModeButton.target = self
        chrome.roundingModeButton.action = #selector(toggleRoundingMode)
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
        tableView.setAccessibilityLabel("Applications and actions")
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
        calculatorView.translatesAutoresizingMaskIntoConstraints = false
        calculatorView.isHidden = true
        list.addSubview(calculatorView)
        let footer = chrome.footer()
        footer.wantsLayer = true
        footerView = footer
        footer.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(footer)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: list.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            calculatorView.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            calculatorView.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            calculatorView.topAnchor.constraint(equalTo: list.topAnchor),
            calculatorView.bottomAnchor.constraint(equalTo: footer.topAnchor),
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
            list.widthAnchor.constraint(equalTo: resultsContainer.widthAnchor),
            resultsHeightConstraint
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
        isRoundingEnabled = true
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    func controlTextDidChange(_ obj: Notification) { applyQuery() }

    private func applyQuery() {
        let query = chrome.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = !query.isEmpty
        let items = applications.map(LauncherItem.application) + SystemAction.allCases.map(LauncherItem.action)
        let evaluated = Calculator.evaluate(query, timestampUnit: timestampOutputUnit)
        if case .numeric(let previous) = calculation, case .numeric(let current) = evaluated,
           previous.expression == current.expression, previous.value == current.value {
            calculation = .numeric(previous)
        } else {
            calculation = evaluated
        }
        results = isExpanded && calculation == nil ? ApplicationSearch.filter(items, query: query) : []
        calculatorView.isHidden = calculation == nil
        scrollView.isHidden = calculation != nil
        if let calculation { calculatorView.configure(calculation) }
        chrome.setCalculatorMode(calculation != nil)
        chrome.updatePrecision(calculation?.decimalPlaceCount, isRounding: isRoundingEnabled)
        chrome.setTimestampUnitSwitching(canSwitchTimestampUnit ? timestampOutputUnit : nil)
        chrome.openButton.isEnabled = (calculation != nil || !results.isEmpty) && !isOpening
        updateEmptyState(hasQuery: isExpanded)
        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        updateSelection()
        updateResultsVisibility(isExpanded)
        updateResultsHeight()
        onDisplayModeChange?(displayMode)
    }

    private func updateResultsHeight() {
        guard displayMode != .collapsed else { return }
        let height = displayMode.height - LauncherHeaderFooter.searchBarHeight
        guard resultsHeightConstraint.constant != height else { return }
        let footerPosition = displayedFooterPosition()
        // Keep the result rows stationary. Animate only the outer viewport and footer
        // so resizing cannot move the rows above the search bar.
        resultsHeightConstraint.constant = height
        launcherContent.layoutSubtreeIfNeeded()
        animateFooter(from: footerPosition)
    }

    private func displayedFooterPosition() -> CGPoint? {
        guard let layer = footerView?.layer, let reference = launcherContent.layer else { return nil }
        let displayed = layer.presentation() ?? layer
        guard let parent = displayed.superlayer else { return nil }
        return (reference.presentation() ?? reference).convert(displayed.position, from: parent)
    }

    private func animateFooter(from position: CGPoint?) {
        guard let position, let layer = footerView?.layer, let parent = layer.superlayer,
              let reference = launcherContent.layer else { return }
        layer.removeAnimation(forKey: "launcherFooterPosition")
        let duration = Appearance.launcherTransitionDuration(for: view.window)
        guard duration > 0, (view.window?.frame.height ?? 0) > LauncherHeaderFooter.searchBarHeight else { return }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = parent.convert(position, from: reference)
        animation.toValue = layer.position
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "launcherFooterPosition")
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
        statusLabel.isHidden = calculation != nil || !results.isEmpty || !hasQuery
        statusLabel.stringValue = isLoading ? "Finding your applications…"
            : "No applications or actions found\nTry a different name."
    }

    private func updateSelection() {
        let row = tableView.selectedRow
        chrome.updateActionTitle(calculation != nil ? "Copy Answer" : selectedActionTitle(row: row))
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
        guard !isOpening, !isPresentingDialog else { return }
        if calculation != nil {
            copyCalculationAnswer(to: .general)
            return
        }
        let row = tableView.selectedRow
        guard results.indices.contains(row) else { return }
        activate(results[row])
    }

    private func activate(_ item: LauncherItem) {
        if case .application(let app) = item {
            openApplication(app)
        } else if case .action(let action) = item {
            runAction(action)
        }
    }

    func copyCalculationAnswer(to pasteboard: NSPasteboard) {
        guard let answer = calculation?.answer else { return }
        pasteboard.clearContents()
        pasteboard.setString(answer, forType: .string)
        onDismiss?()
    }

    private func selectedActionTitle(row: Int) -> String {
        results.indices.contains(row) ? results[row].buttonTitle : "Open"
    }

    private func openApplication(_ app: ApplicationRecord) {
        isOpening = true
        chrome.openButton.isEnabled = false
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async { self?.finishOpening(app, error: error) }
        }
    }

    private func runAction(_ action: SystemAction) {
        guard action.requiresConfirmation else {
            performAction(action)
            return
        }
        isOpening = true
        chrome.openButton.isEnabled = false
        presentDialog(title: "Empty Trash?",
                      message: "Items in the Trash will be permanently deleted. You can’t undo this action.",
                      buttonTitles: ["Cancel", "Empty Trash"]) { [weak self] response in
            guard let self else { return }
            self.isOpening = false
            self.chrome.openButton.isEnabled = !self.results.isEmpty
            if response == 1 { self.performAction(action) }
        }
    }

    private func performAction(_ action: SystemAction) {
        isOpening = true
        chrome.openButton.isEnabled = false
        onDismiss?()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.actionExecutor.perform(action)
                self.finishAction(action, error: nil)
            } catch {
                self.finishAction(action, error: error)
            }
        }
    }

    private func finishAction(_ action: SystemAction, error: Error?) {
        isOpening = false
        chrome.openButton.isEnabled = !results.isEmpty
        guard let error else { return }
        Task { await errorNotifier.notifyFailure(for: action, error: error) }
    }

    private func finishOpening(_ app: ApplicationRecord, error: Error?) {
        isOpening = false
        chrome.openButton.isEnabled = !results.isEmpty
        onDismiss?()
        guard let error else { return }
        Task { await errorNotifier.notifyLaunchFailure(for: app, error: error) }
    }

    private func presentDialog(title: String, message: String, buttonTitles: [String],
                               onResponse: @escaping (Int) -> Void) {
        guard dialog == nil else { return }
        onDisplayModeChange?(.results)
        let overlay = LauncherDialogView(title: title, message: message, buttonTitles: buttonTitles) { [weak self] response in
            guard let self else { return }
            self.dialog = nil
            self.launcherContent.setAccessibilityHidden(false)
            self.view.window?.makeFirstResponder(self.chrome.searchField)
            self.onDisplayModeChange?(self.displayMode)
            onResponse(response)
        }
        dialog = overlay
        launcherContent.setAccessibilityHidden(true)
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
    }

    func cancelDialog() {
        dialog?.cancelOperation(self)
    }

    @objc private func dismissLauncher() { onDismiss?() }
    @objc private func showSettings() { onShowSettings?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if handleTimestampUnitCommand(commandSelector) { return true }
        if handleRoundingModeCommand(commandSelector) { return true }
        if handlePrecisionCommand(commandSelector) { return true }
        let actions: [Selector: () -> Void] = [
            #selector(NSResponder.moveDown(_:)): { self.moveSelection(by: 1) },
            #selector(NSResponder.moveUp(_:)): { self.moveSelection(by: -1) },
            #selector(NSResponder.insertNewline(_:)): {
                if !self.chrome.isReturnKeyPressed { self.openSelectedApplication() }
            },
            #selector(NSResponder.cancelOperation(_:)): dismissLauncher
        ]
        guard let action = actions[commandSelector] else { return false }
        action()
        return true
    }

    private var canSwitchTimestampUnit: Bool {
        guard case .timestamp(let timestamp) = calculation else { return false }
        return timestamp.direction == .zuluToUnix
    }

    private func handleTimestampUnitCommand(_ selector: Selector) -> Bool {
        let units: [Selector: TimestampCalculation.Unit] = [
            #selector(NSResponder.moveLeft(_:)): .seconds, #selector(NSResponder.moveBackward(_:)): .seconds,
            #selector(NSResponder.moveRight(_:)): .milliseconds, #selector(NSResponder.moveForward(_:)): .milliseconds
        ]
        guard let unit = units[selector], canSwitchTimestampUnit, !isPresentingDialog, !isOpening,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        setTimestampOutputUnit(unit)
        return true
    }

    private func setTimestampOutputUnit(_ unit: TimestampCalculation.Unit) {
        guard timestampOutputUnit != unit else { return }
        timestampOutputUnit = unit
        applyQuery()
        if chrome.searchField.currentEditor() == nil { view.window?.makeFirstResponder(chrome.searchField) }
    }

    private func handlePrecisionCommand(_ selector: Selector) -> Bool {
        let offsets: [Selector: Int] = [
            #selector(NSResponder.moveLeft(_:)): -1, #selector(NSResponder.moveBackward(_:)): -1,
            #selector(NSResponder.moveRight(_:)): 1, #selector(NSResponder.moveForward(_:)): 1
        ]
        guard let offset = offsets[selector], isRoundingEnabled, !isPresentingDialog,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false,
              case .numeric(var numeric) = calculation else { return false }
        numeric.adjustPrecision(by: offset)
        let result = CalculatorResult.numeric(numeric)
        calculation = result
        calculatorView.configure(result)
        chrome.updatePrecision(numeric.decimalPlaceCount, isRounding: isRoundingEnabled)
        return true
    }

    private func handleRoundingModeCommand(_ selector: Selector) -> Bool {
        let modes: [Selector: Bool] = [
            #selector(NSResponder.moveUp(_:)): false,
            #selector(NSResponder.moveDown(_:)): true
        ]
        guard let enabled = modes[selector], !isPresentingDialog, !isOpening,
              calculation?.decimalPlaceCount != nil,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        setRoundingEnabled(enabled)
        return true
    }

    @objc private func toggleRoundingMode() {
        guard !isPresentingDialog, !isOpening, calculation?.decimalPlaceCount != nil else { return }
        setRoundingEnabled(!isRoundingEnabled)
    }

    private func setRoundingEnabled(_ enabled: Bool) {
        isRoundingEnabled = enabled
        if !enabled, case .numeric(var numeric) = calculation {
            numeric.resetPrecision()
            let result = CalculatorResult.numeric(numeric)
            calculation = result
            calculatorView.configure(result)
        }
        chrome.updatePrecision(calculation?.decimalPlaceCount, isRounding: enabled)
        if chrome.searchField.currentEditor() == nil { view.window?.makeFirstResponder(chrome.searchField) }
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
        let item = results[row]
        cell.configure(item: item, icon: icon(for: item), selected: row == tableView.selectedRow)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }

    private func icon(for item: LauncherItem) -> NSImage {
        if let image = iconCache.object(forKey: item.id as NSString) { return image }
        let image: NSImage
        switch item {
        case .application(let app):
            image = NSWorkspace.shared.icon(forFile: app.url.path)
        case .action(let action):
            image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.name) ?? NSImage()
        }
        image.size = NSSize(width: 64, height: 64)
        iconCache.setObject(image, forKey: item.id as NSString)
        return image
    }
}
