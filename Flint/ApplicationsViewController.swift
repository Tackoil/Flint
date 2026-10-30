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
    private struct ResultInput {
        let query: String
        let calculation: CalculatorResult
        let colorFormat: ColorConversion.Format?
        let numberBaseFormat: NumberBaseConversion.Format?
        let timestampUnit: TimestampCalculation.Unit
        let isRoundingEnabled: Bool
        let isColorSwitchingEnabled: Bool
        let isNumberBaseSwitchingEnabled: Bool
    }

    var onDismiss: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onCreateQuickLink: (() -> Void)?
    var onShowTranslationSettings: (() -> Void)?
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
    private let translationView = TranslationResultView()
    private let qrCodeView = QRCodeResultView()
    private(set) var isQRCodeMode = false
    private let translationPreferences: TranslationPreferences
    let translationSession: TranslationSession
    private(set) var isTranslationMode = false
    private var isTranslationLanguageSwitchingEnabled = true
    private var translationSwitchDirection = 0
    private var calculation: CalculatorResult?
    private var resultInputs: [ResultInput] = []
    private var colorOutputFormat: ColorConversion.Format?
    private var numberBaseOutputFormat: NumberBaseConversion.Format?
    private var isNumberBaseSwitchingEnabled = true
    private var isColorSwitchingEnabled = true
    private var isRoundingEnabled = true
    private var timestampOutputUnit = TimestampCalculation.Unit.seconds
    private let statusLabel = Appearance.label("Finding your applications…", size: 14)
    private let iconCache = NSCache<NSString, NSImage>()
    private var applications: [ApplicationRecord] = []
    private let quickLinkStore: QuickLinkStore
    private let openQuickLinkURL: @MainActor (QuickLink, URL, @escaping (Error?) -> Void) -> Void
    private var quickLinkObserver: NSObjectProtocol?
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
        if isQRCodeMode { return .qrCode }
        if isTranslationMode { return .results }
        if calculation != nil { return .calculator }
        return isSearchExpanded ? .results : .collapsed
    }

    init(translationSession: TranslationSession? = nil,
         translationPreferences: TranslationPreferences = TranslationPreferences(),
         quickLinkStore: QuickLinkStore = QuickLinkStore(),
         openQuickLinkURL: @escaping @MainActor (QuickLink, URL, @escaping (Error?) -> Void) -> Void = QuickLinkOpener.open) {
        self.translationSession = translationSession ?? TranslationSession()
        self.translationPreferences = translationPreferences
        self.quickLinkStore = quickLinkStore
        self.openQuickLinkURL = openQuickLinkURL
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        if let quickLinkObserver { NotificationCenter.default.removeObserver(quickLinkObserver) }
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

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
        chrome.useResultButton.target = self
        chrome.useResultButton.action = #selector(useCalculationResult)
        chrome.resultBackButton.target = self
        chrome.resultBackButton.action = #selector(restorePreviousInput)
        chrome.settingsButton.target = self
        chrome.settingsButton.action = #selector(showSettings)
        chrome.roundingModeButton.target = self
        chrome.roundingModeButton.action = #selector(toggleRoundingMode)
        chrome.colorModeButton.target = self
        chrome.colorModeButton.action = #selector(toggleColorSwitchingMode)
        chrome.numberBaseModeButton.target = self
        chrome.numberBaseModeButton.action = #selector(toggleNumberBaseSwitchingMode)
        chrome.qrCodeExitButton.target = self
        chrome.qrCodeExitButton.action = #selector(exitQRCodeMode)
        chrome.translationExitButton.target = self
        chrome.translationExitButton.action = #selector(exitTranslationMode)
        chrome.translationModeButton.target = self
        chrome.translationModeButton.action = #selector(toggleTranslationLanguageSwitchingMode)
        chrome.quickLinkQueries.onSubmit = { [weak self] in
            guard let self, !self.chrome.isReturnKeyPressed else { return }
            self.openSelectedApplication()
        }
        chrome.quickLinkBackButton.target = self
        chrome.quickLinkBackButton.action = #selector(moveToPreviousQuery)
        chrome.quickLinkQueries.onEscape = { [weak self] in
            guard let self, !self.chrome.isQuickLinkEscapeKeyPressed else { return }
            self.moveToPreviousQuery()
        }
        chrome.quickLinkQueries.onReturnToSearch = { [weak self] in self?.focusSearchAfterQueries() }
        chrome.quickLinkQueries.onFocusChange = { [weak self] in
            guard let self else { return }
            if self.chrome.quickLinkQueries.isEditing { self.prepareToEditQueries() }
            self.updateSelection()
        }
        translationView.onExit = { [weak self] in self?.exitTranslationMode() }
        translationSession.onChange = { [weak self] in self?.applyQuery() }
        quickLinkObserver = NotificationCenter.default.addObserver(forName: QuickLinkStore.didChange,
                                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.iconCache.removeAllObjects()
                self?.applyQuery()
            }
        }
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
        tableView.setAccessibilityLabel("Applications, quick links, and actions")
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
        translationView.translatesAutoresizingMaskIntoConstraints = false
        translationView.isHidden = true
        list.addSubview(translationView)
        qrCodeView.translatesAutoresizingMaskIntoConstraints = false
        qrCodeView.isHidden = true
        list.addSubview(qrCodeView)
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
            qrCodeView.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            qrCodeView.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            qrCodeView.topAnchor.constraint(equalTo: list.topAnchor),
            qrCodeView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            translationView.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            translationView.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            translationView.topAnchor.constraint(equalTo: list.topAnchor),
            translationView.bottomAnchor.constraint(equalTo: footer.topAnchor),
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
        chrome.setQuickLinkQueries(nil)
        resultInputs.removeAll()
        isRoundingEnabled = true
        colorOutputFormat = nil
        numberBaseOutputFormat = nil
        isNumberBaseSwitchingEnabled = true
        isColorSwitchingEnabled = true
        isTranslationMode = false
        isQRCodeMode = false
        isTranslationLanguageSwitchingEnabled = true
        translationSession.cancel()
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    func controlTextDidChange(_ obj: Notification) { applyQuery() }

    private func applyQuery() {
        let query = chrome.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = isTranslationMode || isQRCodeMode || !query.isEmpty
        updateQueryContent(query, isExpanded: isExpanded)
        updateToolViews()
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

    private func updateQueryContent(_ query: String, isExpanded: Bool) {
        translationSession.update(query: isTranslationMode ? TranslationQuery(text: chrome.searchField.stringValue) : nil,
                                  language: translationPreferences.targetLanguage,
                                  isComposing: (chrome.searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true)
        if isTranslationMode || isQRCodeMode {
            calculation = nil
            results = []
            return
        }
        let items = applications.map(LauncherItem.application) + SystemAction.allCases.map(LauncherItem.action)
            + quickLinkStore.links.map(LauncherItem.quickLink) + [.translation, .createQuickLink, .qrCode]
        let evaluated = Calculator.evaluate(query, timestampUnit: timestampOutputUnit, colorFormat: colorOutputFormat,
                                            numberBaseFormat: numberBaseOutputFormat)
        if case .numeric(let previous) = calculation, case .numeric(let current) = evaluated,
           previous.expression == current.expression, previous.value == current.value {
            calculation = .numeric(previous)
        } else {
            calculation = evaluated
        }
        results = isExpanded && calculation == nil ? ApplicationSearch.filter(items, query: query) : []
    }

    private func updateToolViews() {
        calculatorView.isHidden = calculation == nil
        scrollView.isHidden = calculation != nil || isTranslationMode || isQRCodeMode
        translationView.isHidden = !isTranslationMode
        qrCodeView.isHidden = !isQRCodeMode
        qrCodeView.configure(text: isQRCodeMode ? chrome.searchField.stringValue : "")
        chrome.setTranslationMode(isTranslationMode)
        chrome.setQRCodeMode(isQRCodeMode)
        chrome.setTranslationLanguageSwitching(isTranslationMode ? translationPreferences : nil,
                                               isEnabled: isTranslationLanguageSwitchingEnabled)
        if isTranslationMode {
            translationView.configure(translationSession, preferences: translationPreferences, direction: translationSwitchDirection)
        }
        if let calculation { calculatorView.configure(calculation) }
        chrome.setCalculatorMode(calculation != nil, isColor: colorConversion != nil, isTranslation: isTranslationMode, isQRCode: isQRCodeMode)
        chrome.setColorFormatSwitching(colorConversion?.format, isEnabled: isColorSwitchingEnabled)
        chrome.setNumberBaseSwitching(numberBaseConversion?.format, isEnabled: isNumberBaseSwitchingEnabled)
        chrome.updatePrecision(calculation?.decimalPlaceCount, isRounding: isRoundingEnabled)
        chrome.setTimestampUnitSwitching(canSwitchTimestampUnit ? timestampOutputUnit : nil)
        chrome.setResultBackAvailable(!resultInputs.isEmpty && !isTranslationMode && !isQRCodeMode)
        chrome.openButton.isEnabled = (calculation != nil || !results.isEmpty) && !isOpening
        if isQRCodeMode { chrome.openButton.isEnabled = qrCodeView.code != nil }
        if isTranslationMode {
            chrome.openButton.isEnabled = translationSession.state.canPerformAction
        }
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
        statusLabel.isHidden = isTranslationMode || isQRCodeMode || calculation != nil || !results.isEmpty || !hasQuery
        statusLabel.stringValue = isLoading ? "Finding your applications…"
            : "No applications, quick links, or actions found\nTry a different name."
    }

    private func updateSelection() {
        let row = tableView.selectedRow
        chrome.setQuickLinkQueries(selectedQueryLink)
        chrome.updateActionTitle(conversionActionTitle(row: row), hint: selectedToolUsesTab ? .tab : .returnKey)
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.location != NSNotFound else { return }
        for index in visible.location..<NSMaxRange(visible) {
            let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? ApplicationRowContent
            cell?.updateSelection(index == row)
        }
    }

    private var selectedToolUsesTab: Bool { selectedItem == .translation || selectedItem == .qrCode }

    private func conversionActionTitle(row: Int) -> String {
        if isQRCodeMode { return "Copy QR Code" }
        if isTranslationMode { return translationActionTitle }
        if colorConversion != nil { return "Copy Color" }
        if numberBaseConversion != nil { return "Copy Number" }
        return calculation != nil ? "Copy Answer" : selectedActionTitle(row: row)
    }

    private var colorConversion: ColorConversion? {
        guard case .color(let color) = calculation else { return nil }
        return color
    }

    private var numberBaseConversion: NumberBaseConversion? {
        guard case .numberBase(let number) = calculation else { return nil }
        return number
    }

    @objc private func openClickedApplication() {
        guard tableView.clickedRow >= 0 else { return }
        openSelectedApplication()
    }

    @objc private func openSelectedApplication() {
        guard !isOpening, !isPresentingDialog else { return }
        if isQRCodeMode { copyQRCode(to: .general); return }
        if isTranslationMode {
            performTranslationAction()
            return
        }
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
            return
        }
        if case .action(let action) = item {
            runAction(action)
            return
        }
        activateUtility(item)
    }

    private func activateUtility(_ item: LauncherItem) {
        if case .quickLink(let link) = item { openQuickLink(link); return }
        if item == .createQuickLink { onCreateQuickLink?(); return }
        if item == .translation { enterTranslationMode() }
        if item == .qrCode { enterQRCodeMode() }
    }

    private var selectedQueryLink: QuickLink? {
        guard !isTranslationMode, !isQRCodeMode, calculation == nil, case .quickLink(let link) = selectedItem,
              !link.arguments.isEmpty else { return nil }
        return link
    }

    private func openQuickLink(_ link: QuickLink) {
        guard !link.arguments.isEmpty else { resolveQuickLink(link, values: [:]); return }
        chrome.setQuickLinkQueries(link)
        prepareToEditQueries()
        guard !chrome.quickLinkQueries.focusFirstMissing() else { return }
        resolveQuickLink(link, values: chrome.quickLinkQueries.values)
    }

    private func prepareToEditQueries() {
        resultInputs.removeAll()
        chrome.setResultBackAvailable(false)
    }

    @objc private func moveToPreviousQuery() { chrome.quickLinkQueries.moveLeft() }

    private func focusSearchAfterQueries() {
        view.window?.makeFirstResponder(chrome.searchField)
        updateSelection()
    }

    private func handleQuickLinkCommand(_ selector: Selector, textView: NSTextView) -> Bool {
        guard selector == #selector(NSResponder.insertTab(_:)), !textView.hasMarkedText(),
              !isOpening, !isPresentingDialog, let link = selectedQueryLink,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        if NSApp.currentEvent?.isARepeat != true {
            prepareToEditQueries()
            completeQuickLinkSearch(link)
            chrome.quickLinkQueries.focusFirst()
        }
        return true
    }

    private func completeQuickLinkSearch(_ link: QuickLink) {
        guard chrome.searchField.stringValue != link.name else { return }
        chrome.animateQueryCompletion {
            let values = chrome.quickLinkQueries.values
            chrome.searchField.stringValue = link.name
            applyQuery()
            guard let row = results.firstIndex(of: .quickLink(link)) else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            updateSelection()
            chrome.quickLinkQueries.restoreValues(values)
        }
    }

    private func resolveQuickLink(_ link: QuickLink, values: [String: String]) {
        do {
            let url = try link.resolvedURL(values: values)
            isOpening = true
            chrome.openButton.isEnabled = false
            openQuickLinkURL(link, url) { [weak self] error in
                guard let self else { return }
                self.isOpening = false
                self.chrome.openButton.isEnabled = !self.results.isEmpty
                self.updateSelection()
                if let error {
                    self.showQuickLinkError(link, error: error)
                } else {
                    self.onDismiss?()
                }
            }
        } catch {
            showQuickLinkError(link, error: error)
        }
    }

    private func showQuickLinkError(_ link: QuickLink, error: Error) {
        presentDialog(title: "Couldn’t open \(link.name)", message: error.localizedDescription,
                      buttonTitles: ["OK"]) { _ in }
    }

    private var translationActionTitle: String {
        if translationSession.state.answer != nil { return "Copy Translation" }
        if translationSession.state == .loading { return "Translating…" }
        if translationSession.state == .waiting { return "Waiting…" }
        if translationSession.state == .needsAPIKey { return "Open Settings" }
        if case .failed = translationSession.state { return "Try Again" }
        return "Copy Translation"
    }

    private func performTranslationAction() {
        if translationSession.state == .needsAPIKey { showTranslationSettings(); return }
        if translationSession.state.answer != nil {
            copyTranslationAnswer(to: .general)
            return
        }
        if case .failed = translationSession.state { translationSession.submit() }
    }

    func copyTranslationAnswer(to pasteboard: NSPasteboard) {
        guard let answer = translationSession.state.answer else { return }
        pasteboard.clearContents()
        pasteboard.setString(answer, forType: .string)
        onDismiss?()
    }

    private func enterQRCodeMode() {
        resultInputs.removeAll()
        isQRCodeMode = true
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    @objc private func exitQRCodeMode() {
        isQRCodeMode = false
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    func copyQRCode(to pasteboard: NSPasteboard) {
        guard isQRCodeMode, let code = qrCodeView.code else { return }
        pasteboard.clearContents()
        pasteboard.setData(code.pngData, forType: .png)
        onDismiss?()
    }

    private func enterTranslationMode() {
        resultInputs.removeAll()
        isTranslationMode = true
        isTranslationLanguageSwitchingEnabled = true
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    @objc private func exitTranslationMode() {
        isTranslationMode = false
        chrome.searchField.stringValue = ""
        applyQuery()
        view.window?.makeFirstResponder(chrome.searchField)
    }

    func cancelTranslation() { translationSession.cancel() }

    @objc private func showTranslationSettings() {
        onShowTranslationSettings?()
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
        if (isTranslationMode || isQRCodeMode) && textView.hasMarkedText() { return false }
        animateTabFeedback(for: commandSelector, editor: textView)
        if handleResultBackCommand(commandSelector) { return true }
        if handleResultInsertionCommand(commandSelector, textView: textView) { return true }
        if handleQuickLinkCommand(commandSelector, textView: textView) { return true }
        if handleToolCommand(commandSelector) { return true }
        if handleTranslationNavigationCommand(commandSelector) { return true }
        if handleConversionCommand(commandSelector) { return true }
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

    private func handleConversionCommand(_ selector: Selector) -> Bool {
        handleNumberBaseModeCommand(selector) || handleNumberBaseFormatCommand(selector)
            || handleColorModeCommand(selector) || handleColorFormatCommand(selector)
            || handleTimestampUnitCommand(selector) || handleRoundingModeCommand(selector)
            || handlePrecisionCommand(selector)
    }

    private func animateTabFeedback(for selector: Selector, editor: NSTextView) {
        guard selector == #selector(NSResponder.insertTab(_:)), !editor.hasMarkedText(),
              NSApp.currentEvent?.isARepeat != true,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else { return }
        Appearance.pulseLauncherGlow(on: view)
    }

    private func handleResultInsertionCommand(_ selector: Selector, textView: NSTextView) -> Bool {
        guard selector == #selector(NSResponder.insertTab(_:)), !isOpening, !isPresentingDialog,
              !textView.hasMarkedText(),
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false,
              calculation != nil else { return false }
        if !chrome.isResultTabKeyPressed { insertCalculationResult(in: textView) }
        return true
    }

    @objc private func useCalculationResult() {
        guard !isOpening, !isPresentingDialog, calculation != nil else { return }
        view.window?.makeFirstResponder(chrome.searchField)
        guard let editor = chrome.searchField.currentEditor() as? NSTextView else { return }
        insertCalculationResult(in: editor)
    }

    private func insertCalculationResult(in editor: NSTextView) {
        guard !isOpening, !isPresentingDialog, !editor.hasMarkedText(), let calculation else { return }
        if editor.string != calculation.answer {
            resultInputs.append(ResultInput(query: editor.string, calculation: calculation,
                                           colorFormat: colorOutputFormat, numberBaseFormat: numberBaseOutputFormat,
                                           timestampUnit: timestampOutputUnit, isRoundingEnabled: isRoundingEnabled,
                                           isColorSwitchingEnabled: isColorSwitchingEnabled,
                                           isNumberBaseSwitchingEnabled: isNumberBaseSwitchingEnabled))
        }
        editor.insertText(calculation.answer, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }

    private func handleResultBackCommand(_ selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), !resultInputs.isEmpty,
              !isTranslationMode, !isOpening, !isPresentingDialog else { return false }
        if !chrome.isResultBackKeyPressed { restorePreviousInput() }
        return true
    }

    @objc private func restorePreviousInput() {
        guard !isTranslationMode, !isOpening, !isPresentingDialog, !resultInputs.isEmpty else { return }
        view.window?.makeFirstResponder(chrome.searchField)
        guard let editor = chrome.searchField.currentEditor() as? NSTextView, !editor.hasMarkedText(),
              let previous = resultInputs.popLast() else { return }
        calculation = previous.calculation
        colorOutputFormat = previous.colorFormat
        numberBaseOutputFormat = previous.numberBaseFormat
        timestampOutputUnit = previous.timestampUnit
        isRoundingEnabled = previous.isRoundingEnabled
        isColorSwitchingEnabled = previous.isColorSwitchingEnabled
        isNumberBaseSwitchingEnabled = previous.isNumberBaseSwitchingEnabled
        editor.insertText(previous.query, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }

    private func handleToolCommand(_ selector: Selector) -> Bool {
        if isQRCodeMode {
            let exits = selector == #selector(NSResponder.cancelOperation(_:))
                || (selector == #selector(NSResponder.deleteBackward(_:)) && chrome.searchField.stringValue.isEmpty)
            if exits { exitQRCodeMode(); return true }
            return selector == #selector(NSResponder.insertTab(_:))
        }
        if selectedItem == .qrCode && selector == #selector(NSResponder.insertTab(_:)) {
            enterQRCodeMode()
            return true
        }
        return handleTranslationCommand(selector)
    }

    private func handleTranslationCommand(_ selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTab(_:)) {
            if !isTranslationMode, selectedItem == .translation { enterTranslationMode() }
            return true
        }
        if isTranslationMode {
            let exits = selector == #selector(NSResponder.cancelOperation(_:))
                || (selector == #selector(NSResponder.deleteBackward(_:)) && chrome.searchField.stringValue.isEmpty)
            if exits { exitTranslationMode(); return true }
            return false
        }
        return selector == #selector(NSResponder.insertNewline(_:)) && selectedItem == .translation
    }

    private var selectedItem: LauncherItem? {
        let row = tableView.selectedRow
        return results.indices.contains(row) ? results[row] : nil
    }

    private func handleTranslationNavigationCommand(_ selector: Selector) -> Bool {
        guard isTranslationMode, !isPresentingDialog, !isOpening,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        let modes: [Selector: Bool] = [
            #selector(NSResponder.moveUp(_:)): false, #selector(NSResponder.moveDown(_:)): true
        ]
        if let enabled = modes[selector] {
            chrome.performAfterKeyRelease(enabled ? .downArrow : .upArrow) { [weak self] in
                guard self?.isTranslationMode == true else { return }
                self?.setTranslationLanguageSwitchingEnabled(enabled)
            }
            return true
        }
        return handleTranslationLanguageCommand(selector)
    }

    private func handleTranslationLanguageCommand(_ selector: Selector) -> Bool {
        let offsets: [Selector: Int] = [
            #selector(NSResponder.moveLeft(_:)): -1, #selector(NSResponder.moveBackward(_:)): -1,
            #selector(NSResponder.moveRight(_:)): 1, #selector(NSResponder.moveForward(_:)): 1
        ]
        guard let offset = offsets[selector], isTranslationLanguageSwitchingEnabled else { return false }
        chrome.performAfterKeyRelease(offset < 0 ? .leftArrow : .rightArrow) { [weak self] in
            guard let self, self.isTranslationMode, self.isTranslationLanguageSwitchingEnabled else { return }
            self.translationSwitchDirection = offset
            defer { self.translationSwitchDirection = 0 }
            self.translationPreferences.targetLanguage = self.translationPreferences.targetLanguage(shiftedBy: offset)
            self.applyQuery()
        }
        return true
    }

    @objc private func toggleTranslationLanguageSwitchingMode() {
        guard isTranslationMode, !isPresentingDialog, !isOpening else { return }
        setTranslationLanguageSwitchingEnabled(!isTranslationLanguageSwitchingEnabled)
    }

    private func setTranslationLanguageSwitchingEnabled(_ enabled: Bool) {
        isTranslationLanguageSwitchingEnabled = enabled
        chrome.setTranslationLanguageSwitching(translationPreferences, isEnabled: enabled)
        if chrome.searchField.currentEditor() == nil { view.window?.makeFirstResponder(chrome.searchField) }
    }

    private func handleNumberBaseModeCommand(_ selector: Selector) -> Bool {
        let modes: [Selector: Bool] = [
            #selector(NSResponder.moveUp(_:)): false, #selector(NSResponder.moveDown(_:)): true
        ]
        guard let enabled = modes[selector], numberBaseConversion != nil, !isPresentingDialog, !isOpening,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        chrome.performAfterKeyRelease(enabled ? .downArrow : .upArrow) { [weak self] in
            guard self?.numberBaseConversion != nil else { return }
            self?.setNumberBaseSwitchingEnabled(enabled)
        }
        return true
    }

    @objc private func toggleNumberBaseSwitchingMode() {
        guard numberBaseConversion != nil, !isPresentingDialog, !isOpening else { return }
        setNumberBaseSwitchingEnabled(!isNumberBaseSwitchingEnabled)
    }

    private func setNumberBaseSwitchingEnabled(_ enabled: Bool) {
        isNumberBaseSwitchingEnabled = enabled
        chrome.setNumberBaseSwitching(numberBaseConversion?.format, isEnabled: enabled)
        if chrome.searchField.currentEditor() == nil { view.window?.makeFirstResponder(chrome.searchField) }
    }

    private func handleNumberBaseFormatCommand(_ selector: Selector) -> Bool {
        let offsets: [Selector: Int] = [
            #selector(NSResponder.moveLeft(_:)): -1, #selector(NSResponder.moveBackward(_:)): -1,
            #selector(NSResponder.moveRight(_:)): 1, #selector(NSResponder.moveForward(_:)): 1
        ]
        guard let offset = offsets[selector], numberBaseConversion != nil, isNumberBaseSwitchingEnabled,
              !isPresentingDialog, !isOpening,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        chrome.performAfterKeyRelease(offset < 0 ? .leftArrow : .rightArrow) { [weak self] in
            guard let self, let number = self.numberBaseConversion, self.isNumberBaseSwitchingEnabled else { return }
            self.numberBaseOutputFormat = number.format.shifted(by: offset)
            self.applyQuery()
        }
        return true
    }

    private func handleColorModeCommand(_ selector: Selector) -> Bool {
        let modes: [Selector: Bool] = [
            #selector(NSResponder.moveUp(_:)): false, #selector(NSResponder.moveDown(_:)): true
        ]
        guard let enabled = modes[selector], colorConversion != nil, !isPresentingDialog, !isOpening,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        chrome.performAfterKeyRelease(enabled ? .downArrow : .upArrow) { [weak self] in
            self?.setColorSwitchingEnabled(enabled)
        }
        return true
    }

    @objc private func toggleColorSwitchingMode() {
        guard colorConversion != nil, !isPresentingDialog, !isOpening else { return }
        setColorSwitchingEnabled(!isColorSwitchingEnabled)
    }

    private func setColorSwitchingEnabled(_ enabled: Bool) {
        isColorSwitchingEnabled = enabled
        chrome.setColorFormatSwitching(colorConversion?.format, isEnabled: enabled)
        if chrome.searchField.currentEditor() == nil { view.window?.makeFirstResponder(chrome.searchField) }
    }

    private func handleColorFormatCommand(_ selector: Selector) -> Bool {
        let offsets: [Selector: Int] = [
            #selector(NSResponder.moveLeft(_:)): -1, #selector(NSResponder.moveBackward(_:)): -1,
            #selector(NSResponder.moveRight(_:)): 1, #selector(NSResponder.moveForward(_:)): 1
        ]
        guard let offset = offsets[selector], colorConversion != nil, isColorSwitchingEnabled, !isPresentingDialog, !isOpening,
              NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty != false else {
            return false
        }
        chrome.performAfterKeyRelease(offset < 0 ? .leftArrow : .rightArrow) { [weak self] in
            guard let self, let color = self.colorConversion, self.isColorSwitchingEnabled else { return }
            self.colorOutputFormat = color.format.shifted(by: offset)
            self.applyQuery()
        }
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
        chrome.performAfterKeyRelease(unit == .seconds ? .leftArrow : .rightArrow) { [weak self] in
            self?.setTimestampOutputUnit(unit)
        }
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
        chrome.performAfterKeyRelease(enabled ? .downArrow : .upArrow) { [weak self] in
            self?.setRoundingEnabled(enabled)
        }
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
        let image = loadIcon(for: item)
        image.size = NSSize(width: 64, height: 64)
        iconCache.setObject(image, forKey: item.id as NSString)
        return image
    }

    private func loadIcon(for item: LauncherItem) -> NSImage {
        if case .application(let app) = item { return NSWorkspace.shared.icon(forFile: app.url.path) }
        if case .action(let action) = item {
            return NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.name) ?? NSImage()
        }
        if case .quickLink(let link) = item, let url = try? link.resolvedURL(), url.isFileURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let symbols: [LauncherItem: String] = [.translation: "character.bubble", .qrCode: "qrcode"]
        let symbol = symbols[item] ?? "link"
        return NSImage(systemSymbolName: symbol, accessibilityDescription: item.name) ?? NSImage()
    }
}
