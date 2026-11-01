import AppKit

@MainActor
func checkQuickLinks() {
    let suite = "FlintQuickLinkAppearance-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = QuickLinkStore(defaults: defaults)
    checkQuickLinkSearch(store)
    checkQuickLinkArguments(store)
    checkQuickLinkCompletionAndHighlight(store)
    checkQuickLinkFocusGlow()
    checkQuickLinkQueryAnimation()
    checkQuickLinkFailure(store)
    checkQuickLinkEditor(store)
    checkQuickLinkSettings(store)
    print("PASS: quick links search, launch, refresh after edits, edit queries in the search bar, navigate with Tab, validate, and persist")
}

@MainActor
private func checkQuickLinkSearch(_ store: QuickLinkStore) {
    var link = QuickLink(name: "Flint Dashboard", link: "https://example.com/dashboard")
    try! store.save(link)
    var opened: URL?
    var dismissed = false
    var created = false
    let controller = ApplicationsViewController(quickLinkStore: store, openQuickLinkURL: { _, url, done in
        opened = url
        done(nil)
    })
    controller.onDismiss = { dismissed = true }
    controller.onCreateQuickLink = { created = true }
    let window = quickLinkWindow(controller: controller)
    let search = quickLinkViews(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let table = quickLinkViews(controller.view).compactMap { $0 as? NSTableView }.first!
    quickLinkSearch("Flint Dashboard", controller: controller, search: search)
    precondition(table.numberOfRows == 1)
    controller.view.layoutSubtreeIfNeeded()
    renderQuickLinkPreview(controller.view, name: "launcher")
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(opened?.absoluteString == link.link && dismissed)
    link.name = "Changed Dashboard"
    try! store.save(link)
    precondition(table.numberOfRows == 0, "Saving an edit must refresh the current query immediately")
    quickLinkSearch("Changed Dashboard", controller: controller, search: search)
    precondition(table.numberOfRows == 1)
    try! store.remove(id: link.id)
    precondition(table.numberOfRows == 0)
    quickLinkSearch("Create Quick Link", controller: controller, search: search)
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(created)
    window.orderOut(nil)
}

@MainActor
private func checkQuickLinkArguments(_ store: QuickLinkStore) {
    let link = QuickLink(name: "Find Repository", link: "https://example.com/{org}/{repo}")
    try! store.save(link)
    var opened: URL?
    var dismissed = false
    let controller = ApplicationsViewController(quickLinkStore: store, openQuickLinkURL: { _, url, done in
        opened = url
        done(nil)
    })
    controller.onDismiss = { dismissed = true }
    let window = quickLinkWindow(controller: controller)
    let search = quickLinkViews(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    quickLinkSearch(link.name, controller: controller, search: search)
    let bar = quickLinkViews(controller.view).compactMap { $0 as? QuickLinkQueryBar }.first!
    let fields = quickLinkViews(bar).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    precondition(fields.count == 2 && !bar.isHidden && window.attachedSheet == nil)
    controller.view.layoutSubtreeIfNeeded()
    let searchFrame = controller.view.convert(search.bounds, from: search)
    let barFrame = controller.view.convert(bar.bounds, from: bar)
    precondition(abs(searchFrame.midY - barFrame.midY) < 1 && barFrame.minX > searchFrame.maxX,
                 "Queries must appear beside the root input inside the search bar")
    precondition(controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:))))
    precondition(fields[0].currentEditor() != nil && opened == nil)
    fields[0].stringValue = "open ai"
    _ = bar.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    precondition(fields[1].currentEditor() != nil)
    fields[1].stringValue = "flint/core"
    checkQuickLinkQueryNavigation(bar, fields: fields, search: search)
    renderQuickLinkPreview(controller.view, name: "inline-queries")
    _ = bar.control(fields[1], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(opened?.absoluteString == "https://example.com/open%20ai/flint%2Fcore" && dismissed)
    precondition(!controller.isPresentingDialog && window.attachedSheet == nil)
    opened = nil
    dismissed = false
    fields[0].stringValue = ""
    _ = bar.control(fields[1], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(fields[0].currentEditor() != nil && opened == nil && !dismissed)
    controller.resetSearch()
    quickLinkSearch(link.name, controller: controller, search: search)
    precondition(bar.values.values.allSatisfy(\.isEmpty), "Reopening must clear old query values")
    checkQuickLinkQueryHistory(controller: controller, search: search, bar: bar, link: link)
    window.orderOut(nil)
    checkManyQuickLinkQueries(store)
}

@MainActor
private func checkQuickLinkCompletionAndHighlight(_ store: QuickLinkStore) {
    let link = QuickLink(name: "Focus Demo", link: "https://example.com/{first}/{second}")
    try! store.save(link)
    let controller = ApplicationsViewController(quickLinkStore: store)
    let window = quickLinkWindow(controller: controller)
    let search = quickLinkViews(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    quickLinkSearch("focus d", controller: controller, search: search)
    let bar = quickLinkViews(controller.view).compactMap { $0 as? QuickLinkQueryBar }.first!
    bar.focusFirst()
    let original = quickLinkViews(bar).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    original.stringValue = "kept value"
    pressQuickLinkEscape(bar, field: original)
    precondition(search.stringValue == "focus d")
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    let fields = quickLinkViews(bar).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    precondition(search.stringValue == link.name && fields[0].currentEditor() != nil,
                 "The first Tab must complete the selected quick link name and focus its first query")
    precondition(fields[0].stringValue == "kept value", "Completing search must preserve entered queries")
    controller.view.layoutSubtreeIfNeeded()
    let nameWidth = (link.name as NSString).size(withAttributes: [.font: search.font!]).width
    precondition(search.bounds.width >= nameWidth && search.bounds.width < nameWidth + 8,
                 "The completed quick link name must fit without reserving empty input width: \(search.bounds.width) for \(nameWidth)")
    let gap = controller.view.convert(bar.bounds, from: bar).minX - controller.view.convert(search.bounds, from: search).maxX
    precondition(gap > 0 && gap < 8, "The first query must follow the name with word-sized spacing")
    for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
        window.appearance = NSAppearance(named: appearance)
        checkQuickLinkHighlight(bar, field: fields[0])
        renderQuickLinkPreview(controller.view, name: "focused-first-\(appearance.rawValue)")
        _ = bar.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
        checkQuickLinkHighlight(bar, field: fields[1])
        renderQuickLinkPreview(controller.view, name: "focused-second-\(appearance.rawValue)")
        pressQuickLinkEscape(bar, field: fields[1])
        checkQuickLinkHighlight(bar, field: fields[0])
    }
    pressQuickLinkEscape(bar, field: fields[0])
    checkQuickLinkHighlight(bar, field: nil)
    window.orderOut(nil)
}

@MainActor
private func checkQuickLinkHighlight(_ bar: QuickLinkQueryBar, field: NSTextField?) {
    if let field {
        let expected = bar.documentView!.convert(field.bounds, from: field)
        precondition(bar.focusHighlight.targetFrame == expected, "The single outline must target the focused query")
        precondition(bar.focusHighlight.superview?.subviews.last === bar.focusHighlight,
                     "The focus glow must draw above query backgrounds")
    } else {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        precondition(bar.focusHighlight.targetFrame == nil, "Returning to search must clear the query highlight")
    }
}

@MainActor
private func checkQuickLinkFocusGlow() {
    let header = LauncherHeaderFooter()
    let bar = header.searchBar()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 56),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = bar
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    let queries = header.quickLinkQueries
    let link = QuickLink(name: "Focus Animation", link: "https://example.com/{one}/{two}/{three}")
    header.searchField.stringValue = link.name
    header.setQuickLinkQueries(link)
    bar.layoutSubtreeIfNeeded()
    let fields = quickLinkViews(queries).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    queries.onEscape = { [weak queries] in queries?.moveLeft() }
    queries.onReturnToSearch = { window.makeFirstResponder(header.searchField) }
    queries.focusFirst()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    _ = queries.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    checkQuickLinkHighlight(queries, field: fields[1])
    checkFocusedQueryGlow(queries)
    let destination = queries.focusHighlight.frame
    var glowLevels: [Float] = []
    for _ in 0..<20 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.015))
        precondition(queries.focusHighlight.frame == destination, "The glow must stay on the focused query without sliding")
        glowLevels.append(queries.focusHighlight.layer!.shadowOpacity)
    }
    precondition(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || glowLevels.contains { $0 > 0.1 },
                 "The focused query must briefly glow")
    precondition(queries.focusHighlight.layer!.shadowOpacity < 0.001,
                 "The focus glow must blink once and finish")
    _ = queries.control(fields[1], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    RunLoop.current.run(until: Date().addingTimeInterval(0.07))
    _ = queries.control(fields[2], textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    checkQuickLinkHighlight(queries, field: fields[1])
    checkFocusedQueryGlow(queries)
    precondition(fields[1].currentEditor() != nil)
    _ = queries.control(fields[1], textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    _ = queries.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    precondition(queries.focusHighlight.alphaValue == 0 && header.searchField.currentEditor() != nil)
    precondition(queries.focusHighlight.layer?.shadowOpacity == 0)
    print("PASS: Tab and Escape blink a glow only on the focused query, cancel old pulses, and respect Reduce Motion")
}

@MainActor
private func checkFocusedQueryGlow(_ queries: QuickLinkQueryBar) {
    let highlight = queries.focusHighlight
    precondition(highlight.frame == highlight.targetFrame, "The focus indicator must switch directly to the new query")
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(highlight.layer?.shadowOpacity == 0)
    }

}

@MainActor
private func checkQuickLinkQueryAnimation() {
    let header = LauncherHeaderFooter()
    let bar = header.searchBar()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 56),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = bar
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    let link = QuickLink(name: "Animate Query Completion", link: "https://example.com/{query}")
    header.searchField.stringValue = "Ani"
    header.setQuickLinkQueries(link)
    bar.layoutSubtreeIfNeeded()
    let initialX = header.quickLinkQueries.frame.minX
    header.quickLinkQueries.onFocusChange = { header.setQuickLinkQueries(link) }
    header.animateQueryCompletion {
        header.searchField.stringValue = link.name
        header.setQuickLinkQueries(link)
    }
    header.quickLinkQueries.focusFirst()
    let field = quickLinkViews(header.quickLinkQueries).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    field.stringValue = "preserved"
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    precondition(reduceMotion || abs(header.quickLinkQueries.frame.minX - initialX) < 2,
                 "Autocomplete must start the query block at its existing position")
    var positions: [CGFloat] = []
    for _ in 0..<20 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.015))
        positions.append(header.quickLinkQueries.frame.minX)
    }
    let finalX = header.quickLinkQueries.frame.minX
    precondition(finalX > initialX + 20)
    precondition(reduceMotion || positions.contains { $0 > initialX + 1 && $0 < finalX - 1 },
                 "The query block must move through intermediate positions")
    precondition(field.currentEditor() != nil && field.stringValue == "preserved")
    checkQuickLinkHighlight(header.quickLinkQueries, field: field)
    checkInterruptedQueryAnimation(header, link: link, bar: bar, reduceMotion: reduceMotion)
    print("PASS: query blocks slide with autocomplete, keep focus and values, reverse smoothly, and respect Reduce Motion")
}

@MainActor
private func checkInterruptedQueryAnimation(_ header: LauncherHeaderFooter, link: QuickLink, bar: NSView, reduceMotion: Bool) {
    header.animateQueryCompletion {
        header.searchField.stringValue = "Ani"
        header.setQuickLinkQueries(link)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.07))
    let interruptedX = header.quickLinkQueries.frame.minX
    header.animateQueryCompletion {
        header.searchField.stringValue = link.name
        header.setQuickLinkQueries(link)
    }
    precondition(reduceMotion || abs(header.quickLinkQueries.frame.minX - interruptedX) < 2,
                 "Interrupting movement must continue from the current query position")
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let field = header.searchField
    let gap = bar.convert(header.quickLinkQueries.bounds, from: header.quickLinkQueries).minX
        - bar.convert(field.bounds, from: field).maxX
    precondition(gap > 0 && gap < 8, "Completed movement must retain word-sized spacing")
}

@MainActor
private func checkQuickLinkQueryHistory(controller: ApplicationsViewController, search: NSTextField,
                                       bar: QuickLinkQueryBar, link: QuickLink) {
    quickLinkSearch("2+2", controller: controller, search: search)
    controller.view.window?.makeFirstResponder(search)
    let editor = search.currentEditor() as! NSTextView
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    precondition(search.stringValue == "4")
    quickLinkSearch(link.name, controller: controller, search: search)
    // Focusing directly follows the same path as clicking a query instead of pressing Tab.
    bar.focusFirst()
    let field = quickLinkViews(bar).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let resultBack = quickLinkViews(controller.view).compactMap { $0 as? NSButton }
        .first { $0.action == NSSelectorFromString("restorePreviousInput") }!
    precondition(resultBack.isHidden, "Calculator history must not capture Escape while editing a query")
    pressQuickLinkEscape(bar, field: field)
    precondition(search.currentEditor() != nil && search.stringValue == link.name)
}

@MainActor
private func checkQuickLinkQueryNavigation(_ bar: QuickLinkQueryBar, fields: [NSTextField], search: NSTextField) {
    _ = bar.control(fields[1], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    precondition(fields[0].currentEditor() != nil, "Tab after the last query wraps to the first")
    _ = bar.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertBacktab(_:)))
    precondition(fields[1].currentEditor() != nil, "Shift-Tab moves to the previous query, wrapping at the first")
    bar.focusFirst()
    _ = bar.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    _ = bar.control(fields[1], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertBacktab(_:)))
    precondition(fields[0].currentEditor() != nil)
    _ = bar.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    pressQuickLinkEscape(bar, field: fields[1])
    precondition(fields[0].currentEditor() != nil && search.currentEditor() == nil,
                 "Escape must move one query left before returning to search")
    pressQuickLinkEscape(bar, field: fields[0])
    precondition(search.currentEditor() != nil && fields[0].stringValue == "open ai" && fields[1].stringValue == "flint/core")
    bar.focusFirst()
    _ = bar.control(fields[0], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
}

@MainActor
private func pressQuickLinkEscape(_ bar: QuickLinkQueryBar, field: NSTextField) {
    let hint = quickLinkViews(bar.window!.contentView!).compactMap { $0 as? KeyboardHintView }
        .first { $0.hint == .escape && !$0.isHiddenOrHasHiddenAncestor }!
    let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                               windowNumber: bar.window!.windowNumber, context: nil, characters: "",
                               charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: bar.window!.windowNumber, context: nil, characters: "",
                             charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    hint.handleKeyEvent(down)
    _ = bar.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    precondition(field.currentEditor() != nil, "Escape waits for release and must not move twice")
    hint.handleKeyEvent(up)
}

@MainActor
private func checkManyQuickLinkQueries(_ store: QuickLinkStore) {
    let link = QuickLink(name: "Many Queries", link: "https://example.com/" + (0..<8).map { "{query\($0)}" }.joined(separator: "/"))
    try! store.save(link)
    let controller = ApplicationsViewController(quickLinkStore: store)
    let window = quickLinkWindow(controller: controller)
    let search = quickLinkViews(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    quickLinkSearch(link.name, controller: controller, search: search)
    let bar = quickLinkViews(controller.view).compactMap { $0 as? QuickLinkQueryBar }.first!
    let fields = quickLinkViews(bar).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    controller.view.layoutSubtreeIfNeeded()
    precondition(fields.count == 8 && controller.view.bounds.width == 760)
    bar.focusFirst()
    for index in 0..<7 {
        _ = bar.control(fields[index], textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    }
    precondition(fields[7].currentEditor() != nil)
    precondition(bar.documentVisibleRect.intersects(fields[7].frame), "Tab must reveal queries that overflow the bar")
    renderQuickLinkPreview(controller.view, name: "many-inline-queries")
    window.orderOut(nil)
}

@MainActor
private func checkQuickLinkFailure(_ store: QuickLinkStore) {
    let link = QuickLink(name: "Missing Project", link: "/tmp/flint-does-not-exist-\(UUID().uuidString)")
    try! store.save(link)
    let controller = ApplicationsViewController(quickLinkStore: store)
    let window = quickLinkWindow(controller: controller)
    let search = quickLinkViews(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    var dismissed = false
    controller.onDismiss = { dismissed = true }
    quickLinkSearch(link.name, controller: controller, search: search)
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(controller.isPresentingDialog && !dismissed)
    controller.cancelDialog()
    precondition(!controller.isPresentingDialog)
    let open = quickLinkViews(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Open Quick Link" }!
    precondition(open.isEnabled, "An opening failure must allow retrying from the footer")
    try! store.remove(id: link.id)
    window.orderOut(nil)
}

@MainActor
private func checkQuickLinkEditor(_ store: QuickLinkStore) {
    checkQuickLinkEditorValidation(store)
    let editor = QuickLinkEditorController(link: nil, store: store)
    let content = editor.window!.contentView!
    let controls = quickLinkViews(content)
    let name = controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link name" }!
    let destination = controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link destination" }!
    let save = controls.compactMap { $0 as? NSButton }.first { $0.title == "Save Quick Link" }!
    let count = store.links.count
    name.stringValue = "Search Google"
    destination.stringValue = "https://google.com/search?q={query}"
    for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
        editor.window?.appearance = NSAppearance(named: appearance)
        renderQuickLinkPreview(content, name: "editor-\(appearance.rawValue)")
        content.layoutSubtreeIfNeeded()
        precondition(content.bounds.width == 480, "The quick-link editor must keep its compact width")
        precondition(content.bounds.contains(content.convert(save.bounds, from: save)))
        precondition(destination.frame.width > 200, "The link field must fill the editor width")
        checkQuickLinkEditorLayout(content)
    }
    save.performClick(nil)
    precondition(store.links.count == count + 1)
    let saved = store.links.last!
    let editing = QuickLinkEditorController(link: saved, store: store)
    let editControls = quickLinkViews(editing.window!.contentView!)
    let editName = editControls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link name" }!
    precondition(editName.stringValue == saved.name)
    editName.stringValue = "Web Search"
    editControls.compactMap { $0 as? NSButton }.first { $0.title == "Save Quick Link" }!.performClick(nil)
    precondition(store.links.last!.id == saved.id && store.links.last!.name == "Web Search")
    checkQuickLinkApplicationControl(store, link: store.links.last!)
    editor.window?.orderOut(nil)
    editing.window?.orderOut(nil)
}

@MainActor
private func checkQuickLinkEditorLayout(_ content: NSView) {
    let controls = quickLinkViews(content)
    let destination = controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link destination" }!
    let buttons = controls.compactMap { $0 as? NSButton }
    let application = buttons.first { $0.accessibilityLabel() == "Open With" }!
    let reset = buttons.first { $0.accessibilityLabel() == "Reset Open With" }!
    let save = buttons.first { $0.title == "Save Quick Link" }!
    let fieldFrame = content.convert(destination.bounds, from: destination)
    let applicationFrame = content.convert(application.bounds, from: application)
    let resetFrame = content.convert(reset.bounds, from: reset)
    precondition(abs(applicationFrame.minX - fieldFrame.minX) < 1)
    precondition(abs(resetFrame.maxX - fieldFrame.maxX) < 1)
    precondition(abs(resetFrame.minX - applicationFrame.maxX - 8) < 1,
                 "Open With must fill the field column up to its reset icon")
    precondition(reset.title.isEmpty && reset.image != nil && application.image != nil)
    precondition(content.bounds.height < 300, "The editor must size to its form instead of leaving unused space")
    precondition(abs(content.convert(save.bounds, from: save).minY - 24) < 2,
                 "The editor must retain only its bottom content padding")
}

@MainActor
private func checkQuickLinkEditorValidation(_ store: QuickLinkStore) {
    let editor = QuickLinkEditorController(link: nil, store: store)
    let content = editor.window!.contentView!
    defer { editor.window?.orderOut(nil) }
    let height = content.bounds.height
    let count = store.links.count
    let save = quickLinkViews(content).compactMap { $0 as? NSButton }.first { $0.title == "Save Quick Link" }!
    save.performClick(nil)
    precondition(store.links.count == count)
    precondition(content.bounds.height > height, "Validation must grow the editor to fit the error")
    checkQuickLinkEditorLayout(content)
    renderQuickLinkPreview(content, name: "editor-validation")
}

@MainActor
private func checkQuickLinkApplicationControl(_ store: QuickLinkStore, link: QuickLink) {
    var link = link
    let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")!
    link.applicationURL = applicationURL
    let editor = QuickLinkEditorController(link: link, store: store)
    let content = editor.window!.contentView!
    defer { editor.window?.orderOut(nil) }
    let buttons = quickLinkViews(content).compactMap { $0 as? NSButton }
    let application = buttons.first { $0.accessibilityLabel() == "Open With" }!
    let reset = buttons.first { $0.accessibilityLabel() == "Reset Open With" }!
    let save = buttons.first { $0.title == "Save Quick Link" }!
    precondition(application.title == applicationURL.deletingPathExtension().lastPathComponent)
    precondition(application.image?.isTemplate == false && application.image?.size == NSSize(width: 16, height: 16))
    precondition(reset.isEnabled)
    let selectedIconFrame = application.cell!.imageRect(forBounds: application.bounds)
    let selectedTitleFrame = application.cell!.titleRect(forBounds: application.bounds)
    for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
        editor.window?.appearance = NSAppearance(named: appearance)
        renderQuickLinkPreview(content, name: "editor-application-\(appearance.rawValue)")
        checkQuickLinkEditorLayout(content)
    }
    save.performClick(nil)
    precondition(store.links.last!.applicationURL == applicationURL)
    reset.performClick(nil)
    precondition(application.title == "Default Application" && !reset.isEnabled)
    checkQuickLinkEditorLayout(content)
    let defaultIconFrame = application.cell!.imageRect(forBounds: application.bounds)
    let defaultTitleFrame = application.cell!.titleRect(forBounds: application.bounds)
    precondition(defaultIconFrame == selectedIconFrame,
                 "Default and selected application icons must occupy the same position")
    precondition(defaultTitleFrame.minX == selectedTitleFrame.minX && defaultTitleFrame.midY == selectedTitleFrame.midY,
                 "The application title must not move when resetting the selection")
    renderQuickLinkPreview(content, name: "editor-reset-\(editor.window!.appearance!.name.rawValue)")
    save.performClick(nil)
    precondition(store.links.last!.applicationURL == nil)
    print("PASS: Open With fills the row, shows the selected app icon, persists selection, and resets with its icon button")
}

@MainActor
private func checkQuickLinkSettings(_ store: QuickLinkStore) {
    let settings = QuickLinkSettingsView(store: store)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                                       styleMask: [.titled], backing: .buffered, defer: false)
    let background = AppearanceSurfaceView(fillColor: .windowBackgroundColor)
    window.contentView = background
    settings.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(settings)
    NSLayoutConstraint.activate([
        settings.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
        settings.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
        settings.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
        settings.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -20)
    ])
    let table = quickLinkViews(settings).compactMap { $0 as? NSTableView }.first!
    precondition(table.numberOfRows == store.links.count)
    AppearanceCheckWindows.show(window)
    for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
        window.appearance = NSAppearance(named: appearance)
        renderQuickLinkPreview(background, name: "library-\(appearance.rawValue)")
        settings.layoutSubtreeIfNeeded()
        let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView
        precondition(cell.imageView?.image != nil && cell.textField?.stringValue == store.links[0].name)
        precondition(cell.bounds.contains(cell.convert(cell.textField!.bounds, from: cell.textField!)))
    }
    let buttons = quickLinkViews(settings).compactMap { $0 as? NSButton }
    precondition(!buttons.contains { ["Edit…", "Delete", "More"].contains($0.title) })
    precondition(table.action == nil && table.doubleAction == nil,
                 "Selecting a row must not open its editor")
    precondition(!settings.responds(to: NSSelectorFromString("tableView:rowActionsForRow:edge:")),
                 "Quick Links must use the same explicit controls as Scripts")
    checkQuickLinkSettingsEditing(settings, table: table, store: store, window: window)
    checkQuickLinkSettingsRemoval(settings, table: table, store: store, window: window)
    window.orderOut(nil)
    let controller = SettingsViewController(preferences: LauncherPreferences(), onShortcutChange: { _ in true },
                                            onRecordingStateChange: { _ in }, onMenuBarVisibilityChange: { _ in })
    let sidebarWindow = quickLinkWindow(controller: controller, width: 720)
    quickLinkViews(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Quick Links" }!.performClick(nil)
    controller.view.layoutSubtreeIfNeeded()
    let library = quickLinkViews(controller.view).compactMap { $0 as? QuickLinkSettingsView }.first!
    precondition(controller.view.bounds.contains(controller.view.convert(library.bounds, from: library)),
                 "Quick Links settings must fit at the minimum window size")
    for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
        sidebarWindow.appearance = NSAppearance(named: appearance)
        renderQuickLinkPreview(controller.view, name: "settings-\(appearance.rawValue)")
    }
    sidebarWindow.orderOut(nil)
}

@MainActor
private func checkQuickLinkSettingsEditing(_ settings: QuickLinkSettingsView, table: NSTableView,
                                          store: QuickLinkStore, window: NSWindow) {
    let original = store.links[0]
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    let originalCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
    quickLinkViews(originalCell).compactMap { $0 as? NSButton }.first { $0.title == "Edit" }!.performClick(nil)
    let sheet = window.attachedSheet!
    precondition(!window.isKeyWindow && !sheet.isKeyWindow,
                 "Editor popups must stay offscreen without taking keyboard focus")
    let controls = quickLinkViews(sheet.contentView!)
    let name = controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link name" }!
    precondition(name.stringValue == original.name)
    name.stringValue = "Renamed from Settings"
    controls.compactMap { $0 as? NSButton }.first { $0.title == "Save Quick Link" }!.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    precondition(window.attachedSheet == nil)
    precondition(store.links[0].id == original.id && store.links[0].name == "Renamed from Settings")
    let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView
    precondition(cell.textField?.stringValue == "Renamed from Settings", "Saving must refresh the row immediately")
    quickLinkViews(cell).compactMap { $0 as? NSButton }.first { $0.title == "Edit" }!.performClick(nil)
    let cancelControls = quickLinkViews(window.attachedSheet!.contentView!)
    cancelControls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link name" }!.stringValue = "Discard me"
    cancelControls.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }!.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    precondition(store.links[0].name == "Renamed from Settings")
    precondition(!window.isKeyWindow, "Editing checks must preserve the user's keyboard focus")
    print("PASS: per-row Edit opens the correct quick link regardless of selection, refreshes after saving, and cancels safely")
}

@MainActor
private func checkQuickLinkSettingsRemoval(_ settings: QuickLinkSettingsView, table: NSTableView,
                                          store: QuickLinkStore, window: NSWindow) {
    let buttons = quickLinkViews(settings).compactMap { $0 as? NSButton }
    let remove = buttons.first { $0.accessibilityLabel() == "Remove Quick Link" }!
    table.deselectAll(nil)
    precondition(!remove.isEnabled)
    let count = store.links.count
    let removedID = store.links.last!.id
    table.selectRowIndexes(IndexSet(integer: count - 1), byExtendingSelection: false)
    precondition(remove.isEnabled && window.attachedSheet == nil)
    remove.performClick(nil)
    precondition(store.links.count == count - 1 && !store.links.contains { $0.id == removedID })
    precondition(table.numberOfRows == count - 1)
    table.deselectAll(nil)
    precondition(!remove.isEnabled)
    buttons.first { $0.title == "Add Quick Link…" }!.performClick(nil)
    let sheet = window.attachedSheet!
    let controls = quickLinkViews(sheet.contentView!)
    let name = controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link name" }!
    precondition(name.stringValue.isEmpty)
    controls.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }!.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    precondition(store.links.count == count - 1 && window.attachedSheet == nil)
    print("PASS: the integrated toolbar adds quick links, removes the selected link, and disables removal without selection")
}

@MainActor
private func quickLinkSearch(_ query: String, controller: ApplicationsViewController, search: NSTextField) {
    search.stringValue = query
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
}

@MainActor
private func quickLinkWindow(controller: NSViewController, width: CGFloat = 760) -> NSWindow {
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 560),
                                       styleMask: [.titled], backing: .buffered, defer: false)
    window.contentViewController = controller
    return window
}

@MainActor
private func quickLinkViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(quickLinkViews) }

@MainActor
private func renderQuickLinkPreview(_ view: NSView, name: String) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_QUICK_LINK_PREVIEW_DIR"] else { return }
    if let window = view.window, window.sheetParent == nil { AppearanceCheckWindows.show(window) }
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = bitmap.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("quick-link-\(name).png"))
}
