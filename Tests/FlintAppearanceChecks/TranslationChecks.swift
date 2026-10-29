import AppKit

@MainActor
func checkTranslationIntegration() {
    checkSearchTabFocus()
    let session = TranslationSession(readAPIKey: { nil })
    let controller = ApplicationsViewController(translationSession: session)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = translationDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? TranslationResultView }.first!
    let exit = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Exit translation mode" }!
    precondition(!views.compactMap { $0 as? NSButton }.contains { ["Translate ×", "Translation Settings…"].contains($0.title) })
    let editor = NSTextView()
    for command in ["translate", "tr", "late", "tl", "TRANSLATE"] {
        controller.resetSearch()
        search.stringValue = command
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(result.isHidden && !controller.isTranslationMode)
        _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        precondition(!controller.isTranslationMode, "Return must not enter the Translate action")
        let hint = translationDescendants(controller.view).compactMap { $0 as? KeyboardHintView }
            .first { $0.label == "Enter Translation" }!
        precondition(hint.hint == .tab)
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        precondition(controller.isTranslationMode && controller.displayMode == .results)
        precondition(search.stringValue.isEmpty && !exit.isHidden && !result.isHidden)
        let exitHint = translationDescendants(exit).compactMap { $0 as? KeyboardHintView }.first!
        precondition(exitHint.hint == .escape && exitHint.label == "Exit" && exit.isEnabled)
        let copy = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Copy Translation" }!
        precondition(exit.superview === copy.superview, "Escape must be inside the action group")
        search.stringValue = "2+2"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(controller.displayMode == .results && session.query?.text == "2+2")
        precondition(session.state == .waiting, "Typing must wait for a pause before making an API request")
        session.submit()
        precondition(session.state == .needsAPIKey)
        let buttons = translationDescendants(controller.view).compactMap { $0 as? NSButton }
        let setup = buttons.first { $0.accessibilityLabel() == "Open Settings" }!
        var openedSettings = false
        controller.onShowTranslationSettings = { openedSettings = true }
        setup.performClick(nil)
        precondition(openedSettings)
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        precondition(!controller.isTranslationMode && controller.displayMode == .collapsed)
        precondition(exit.isHidden && result.isHidden && session.state.answer == nil)
    }
    search.stringValue = "Finder"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
    precondition(!controller.isTranslationMode && search.stringValue == "Finder")
    checkTranslationResultLayout(window: window, controller: controller, search: search, result: result, editor: editor)
    checkTranslationSettingsLayout()
    checkTranslationSuccess()
    print("PASS: Translate uses action search, Tab enters, Return does not enter, input waits for a pause, and missing-key setup and Escape work")
}

@MainActor
private func checkSearchTabFocus() {
    let controller = ApplicationsViewController(translationSession: TranslationSession(readAPIKey: { nil }))
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let search = translationDescendants(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    controller.resetSearch()
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let editor = search.currentEditor() as! NSTextView
    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    precondition(controller.isTranslationMode)
    precondition(window.firstResponder === search.currentEditor(), "Entering Translate with Tab must keep search focused")
    for _ in 0..<2 {
        (search.currentEditor() as! NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition(window.firstResponder === search.currentEditor(), "Tab in Translate must not move focus to another control")
    }
    (search.currentEditor() as! NSTextView).insertText("hello", replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(search.stringValue == "hello", "Typing after Tab must go straight into the search bar")
    controller.resetSearch()
    for query in ["Finder", "2+2", "#abc"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        (search.currentEditor() as! NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition(window.firstResponder === search.currentEditor(), "Tab in search must keep search focused")
        precondition(!controller.isTranslationMode && search.stringValue == query)
    }
    print("PASS: real field-editor Tab commands retain search focus during translation entry, repeated Tabs, and normal search")
}

@MainActor
private func checkTranslationResultLayout(window: NSWindow, controller: ApplicationsViewController,
                                           search: NSTextField, result: TranslationResultView, editor: NSTextView) {
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    window.contentView?.layoutSubtreeIfNeeded()
    let text = translationDescendants(result).compactMap { $0 as? NSTextView }.first!
    precondition(text.isSelectable && !text.isEditable)
    precondition(result.bounds.width > 700 && result.bounds.height > 300)
    let labels = translationDescendants(result).compactMap { $0 as? NSTextField }
    for label in labels where !label.isHiddenOrHasHiddenAncestor {
        precondition(label.frame.width > 0 && label.frame.height > 0)
        precondition(result.bounds.contains(result.convert(label.bounds, from: label)), "Translation text must fit the panel")
    }
    search.stringValue = ""
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
    precondition(!controller.isTranslationMode)
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    let exit = translationDescendants(controller.view).compactMap { $0 as? NSButton }
        .first { $0.accessibilityLabel() == "Exit translation mode" }!
    exit.performClick(nil)
    precondition(!controller.isTranslationMode && controller.displayMode == .collapsed && exit.isHidden)
}

@MainActor
private func checkTranslationSettingsLayout() {
    let controller = SettingsViewController(preferences: LauncherPreferences(), onShortcutChange: { _ in true },
                                            onRecordingStateChange: { _ in }, onMenuBarVisibilityChange: { _ in })
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.showTranslationSettings()
    controller.view.layoutSubtreeIfNeeded()
    precondition(controller.view.bounds.width == 720, "Translation settings must not force the window wider")
    let settings = translationDescendants(controller.view).compactMap { $0 as? TranslationSettingsView }.first!
    precondition(controller.view.bounds.contains(controller.view.convert(settings.bounds, from: settings)))
    let secure = translationDescendants(settings).compactMap { $0 as? NSSecureTextField }.first!
    precondition(secure.stringValue.isEmpty, "Settings must not reveal the stored key")
    renderTranslationPreview(controller.view, name: "settings")
    for child in settings.arrangedSubviews {
        precondition(child.frame.width > 0 && child.frame.height > 0)
        precondition(settings.bounds.insetBy(dx: -1, dy: -1).contains(child.alignmentRect(forFrame: child.frame)),
                     "Translation settings must fit without clipping: \(type(of: child)) \(child.frame) in \(settings.bounds)")
    }
}

@MainActor
private func checkTranslationSuccess() {
    let expected = String(repeating: "Flint 帮助你快速找到应用。\n按下 Tab，开始翻译。\n\n", count: 20)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let source = "Flint helps you find apps quickly.\nPress Tab to start translating."
    let client = DeepSeekTranslationClient { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        precondition(messages.last?["content"] == source, "Multiline source must reach DeepSeek intact")
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": expected], "finish_reason": "stop"]]
        ])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let session = TranslationSession(client: client, readAPIKey: { "test-key" })
    let controller = ApplicationsViewController(translationSession: session)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = translationDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let editor = NSTextView()
    search.stringValue = "tr"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    search.stringValue = source
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(session.state == .waiting)
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(session.state == .waiting, "Return must not bypass automatic translation's pause")
    let timeout = Date().addingTimeInterval(3)
    while session.state.answer == nil && Date() < timeout {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(session.state.answer == expected)
    controller.view.layoutSubtreeIfNeeded()
    let result = views.compactMap { $0 as? TranslationResultView }.first!
    precondition(search.frame.height < 40, "Multiline source text must stay inside the search bar")
    let text = translationDescendants(result).compactMap { $0 as? NSTextView }.first!
    precondition(text.string == expected && !text.isHiddenOrHasHiddenAncestor)
    precondition(text.enclosingScrollView!.bounds.height > 200)
    precondition(text.frame.height > text.enclosingScrollView!.bounds.height, "Long translations must scroll")
    let copy = translationDescendants(controller.view).compactMap { $0 as? NSButton }
        .first { $0.accessibilityLabel() == "Copy Translation" }!
    precondition(copy.isEnabled)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    var dismissed = false
    controller.onDismiss = { dismissed = true }
    controller.copyTranslationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == expected && dismissed)
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        renderTranslationPreview(controller.view, name: name)
    }
    window.makeFirstResponder(search)
    (search.currentEditor() as! NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:)))
    precondition(window.firstResponder === search.currentEditor(), "Tab must keep search focused when translation output is selectable")
    precondition(session.state.answer == expected)
    search.stringValue = "new text"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(session.state == .waiting && session.state.answer == nil && text.string.isEmpty)
    controller.resetSearch()
    precondition(!controller.isTranslationMode && controller.displayMode == .collapsed)
    print("PASS: translation starts automatically after a pause, with scrollable output, exact copying, edit invalidation, and reopening reset")
}

@MainActor
private func renderTranslationPreview(_ view: NSView, name: String) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_TRANSLATION_PREVIEW_DIR"] else { return }
    if let window = view.window { AppearanceCheckWindows.show(window) }
    defer { view.window?.orderOut(nil) }
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = bitmap.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("translation-\(name).png"))
}

@MainActor
private func translationDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(translationDescendants)
}
