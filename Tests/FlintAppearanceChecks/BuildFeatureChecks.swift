import AppKit

@MainActor
func checkBuildFeatures() {
    let suite = "FlintBuildFeatures-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let links = QuickLinkStore(defaults: defaults)
    try! links.save(QuickLink(name: "Flint Build Selection Fixture", link: "https://example.com"))
    checkFeatureSearch(defaults: defaults, links: links)
    checkFeatureSettings(defaults: defaults, links: links)
    print("PASS: selected build features control search, calculations, tool entry, Settings sections, and contiguous keyboard navigation")
}

@MainActor
private func checkFeatureSearch(defaults: UserDefaults, links: QuickLinkStore) {
    let controller = ApplicationsViewController(translationSession: TranslationSession(readAPIKey: { nil }),
        translationPreferences: TranslationPreferences(defaults: defaults), quickLinkStore: links,
        scriptStore: ScriptCommandStore(defaults: defaults))
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    AppearanceCheckWindows.show(window)
    defer { window.close() }
    let views = buildFeatureViews(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let table = views.compactMap { $0 as? NSTableView }.first!
    let tools: [(String, Bool)] = [
        ("Translate", BuildFeatures.translation), ("QR Code Generator", BuildFeatures.qrCode),
        ("Create Quick Link", BuildFeatures.quickLinks), ("Script Commands", BuildFeatures.scripts),
        ("Show Desktop", BuildFeatures.systemActions), ("Flint Build Selection Fixture", BuildFeatures.quickLinks)
    ]
    for (query, enabled) in tools {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        let names = (0..<table.numberOfRows).flatMap { row in
            buildFeatureViews(controller.tableView(table, viewFor: nil, row: row)!)
                .compactMap { ($0 as? NSTextField)?.stringValue }
        }
        precondition(names.contains(query) == enabled, "Unexpected build availability for \(query)")
    }
    checkFeatureCalculations(controller: controller, search: search)
    checkFeatureToolEntry(controller: controller, search: search, query: "Translate", enabled: BuildFeatures.translation)
    checkFeatureToolEntry(controller: controller, search: search, query: "QR Code Generator", enabled: BuildFeatures.qrCode)
    precondition(!window.isKeyWindow)
}

@MainActor
private func checkFeatureCalculations(controller: ApplicationsViewController, search: NSTextField) {
    let queries: [(String, Bool)] = [
        ("2+3", BuildFeatures.calculator), ("1710513000", BuildFeatures.timestamps),
        ("#ff6363", BuildFeatures.colors), ("0xff", BuildFeatures.numberBases)
    ]
    for (query, enabled) in queries {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        precondition((controller.displayMode == .calculator) == enabled, "Unexpected calculation routing for \(query)")
    }
    // Explicit base input must never fall through to arithmetic when disabled.
    precondition((Calculator.evaluate("0b1010") != nil) == BuildFeatures.numberBases)
}

@MainActor
private func checkFeatureToolEntry(controller: ApplicationsViewController, search: NSTextField, query: String, enabled: Bool) {
    controller.resetSearch()
    search.stringValue = query
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    let entered = query == "Translate" ? controller.isTranslationMode : controller.isQRCodeMode
    precondition(entered == enabled)
    controller.resetSearch()
}

@MainActor
private func checkFeatureSettings(defaults: UserDefaults, links: QuickLinkStore) {
    let translation = TranslationSettingsView(preferences: TranslationPreferences(defaults: defaults),
        hasAPIKey: { false }, saveAPIKey: { _ in }, deleteAPIKey: {})
    let controller = SettingsViewController(preferences: LauncherPreferences(defaults: defaults),
        onShortcutChange: { _ in true }, onRecordingStateChange: { _ in }, onMenuBarVisibilityChange: { _ in },
        scriptStore: ScriptCommandStore(defaults: defaults), quickLinkStore: links, translationSettings: translation)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    AppearanceCheckWindows.show(window)
    defer { window.close() }
    let keyboard = controller.view as! SettingsKeyboardView
    let sections = [("General", true), ("Quick Links", BuildFeatures.quickLinks),
                    ("Scripts", BuildFeatures.scripts), ("Translation", BuildFeatures.translation)]
        .filter { $0.1 }.map { $0.0 }
    let shortcuts = keyboard.actions().filter { !$0.showsInMenu }
    precondition(shortcuts.map(\.title) == sections)
    precondition(shortcuts.map(\.key) == (1...sections.count).map(String.init))
    for action in shortcuts {
        action.perform()
        precondition(keyboard.sidebarControl()?.accessibilityLabel() == action.title)
        precondition(keyboard.controls().last === keyboard.sidebarControl())
    }
    keyboard.focus(keyboard.sidebarControl()!)
    for name in sections.reversed() {
        precondition(keyboard.focusedControl?.accessibilityLabel() == name)
        _ = keyboard.onSectionArrow?(keyboard.focusedControl!, -1)
    }
    controller.createQuickLink()
    if !BuildFeatures.quickLinks { precondition(keyboard.sidebarControl()?.accessibilityLabel() == "General") }
    // Restore General before checking unavailable programmatic destinations.
    shortcuts[0].perform()
    if !BuildFeatures.translation { controller.showTranslationSettings() }
    if !BuildFeatures.scripts { controller.showScriptSettings() }
    precondition(keyboard.sidebarControl()?.accessibilityLabel() == "General")
    renderBuildFeatureSettings(keyboard, window: window)
    precondition(!window.isKeyWindow)
}

@MainActor
private func renderBuildFeatureSettings(_ view: NSView, window: NSWindow) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_BUILD_FEATURE_PREVIEW_DIR"] else { return }
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        window.appearance = NSAppearance(named: name)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("features-\(name.rawValue).png")
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

@MainActor
private func buildFeatureViews(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(buildFeatureViews)
}
