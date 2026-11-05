import AppKit

@MainActor
func checkCalculatorIntegration() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
    let views = calculatorDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? CalculatorResultView }.first!
    let scroll = views.compactMap { $0 as? NSScrollView }.first { $0.documentView is NSTableView }!
    let copy = views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("openSelectedApplication") }!
    let searchIcon = views.compactMap { $0 as? NSImageView }.first { $0.accessibilityLabel() == "Search" }!
    let calculatorIcon = views.compactMap { $0 as? NSImageView }.first { $0.accessibilityLabel() == "Calculator" }!
    var mode = LauncherDisplayMode.collapsed
    controller.onDisplayModeChange = { mode = $0 }
    search.stringValue = "(12 + 8) * 5"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    controller.view.layoutSubtreeIfNeeded()
    precondition(mode == .calculator && !result.isHidden && scroll.isHidden && copy.isEnabled)
    precondition(calculatorIcon.image != nil && calculatorIcon.alphaValue == 1 && searchIcon.alphaValue == 0)
    precondition(copy.accessibilityLabel() == "Copy Answer")
    let labels = calculatorDescendants(of: result).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == "100" })
    precondition(labels.filter { !$0.isHiddenOrHasHiddenAncestor }.count == 2)
    precondition(labels.filter { !$0.isHiddenOrHasHiddenAncestor }.allSatisfy { $0.font?.pointSize == 36 })
    precondition(labels.contains { $0.stringValue == "(12 + 8) × 5" })
    precondition(result.frame.width == 760 && result.frame.height < 180 && result.frame.height > 80,
                 "Calculator frame: \(result.frame); root: \(controller.view.frame)")
    let answer = labels.first { $0.stringValue == "100" }!
    precondition(result.convert(answer.bounds, from: answer).midX > result.bounds.midX)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    var dismissed = false
    controller.onDismiss = { dismissed = true }
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "100" && dismissed)
    dismissed = false
    for query in ["1710513000.123", "0.5", "1710513000.0", "-1", "-0.5", "1969-12-31T23:59:59.999999999Z", "(3)", "1e3", "3+", "1/0", "3f", "1..2+3"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(mode == .results && result.isHidden && !scroll.isHidden,
                     "'\(query)' should stay in normal search")
        precondition(calculatorIcon.alphaValue == 0 && searchIcon.alphaValue == 1)
    }
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "100" && !dismissed)
    search.stringValue = "eject"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(result.isHidden && !scroll.isHidden && copy.isEnabled)
    precondition(copy.accessibilityLabel() == "Run Action")
    precondition(mode == .results && calculatorIcon.alphaValue == 0 && searchIcon.alphaValue == 1)
    search.stringValue = "200*15%"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(mode == .calculator && labels.filter { !$0.isHiddenOrHasHiddenAncestor }.allSatisfy { $0.font?.pointSize == 36 })
    controller.resetSearch()
    precondition(mode == .collapsed && result.isHidden && !copy.isEnabled)
    precondition(calculatorIcon.alphaValue == 0 && searchIcon.alphaValue == 1)
    print("PASS: compact calculator, math typography, matching font sizes, icon changes, copying, errors, and search transitions")
    checkResultInsertion()
    checkResultActionGroup()
    checkResultRestoration()
}

@MainActor
private func checkResultActionGroup() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    controller.resetSearch()
    let views = calculatorDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let button = views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("useCalculationResult") }!
    let copy = views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("openSelectedApplication") }!
    let hint = calculatorDescendants(of: button).compactMap { $0 as? KeyboardHintView }.first!
    precondition(button.isHiddenOrHasHiddenAncestor && button.superview === copy.superview)
    precondition(button.accessibilityLabel() == "Use Result" && hint.hint == .tab)
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        for (query, expected) in [("1/3", "0.3333333333"), ("1710513000", "2024-03-15T14:30:00Z"),
                                  ("0xff", "255"), ("#ff0000", "rgb(255 0 0)")] {
            controller.resetSearch()
            search.stringValue = query
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            precondition(!button.isHiddenOrHasHiddenAncestor && button.isEnabled)
            checkResultActionLayout(controller.view, name: "\(name)-\(query.count)")
            button.performClick(nil)
            let editor = search.currentEditor() as! NSTextView
            precondition(search.stringValue == expected && window.firstResponder === editor)
            precondition(editor.selectedRange() == NSRange(location: expected.utf16.count, length: 0))
        }
    }
    checkResultActionKeyRelease(controller, search: search, hint: hint, window: window)
    for query in ["Finder", "3+", "Translate", ""] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(button.isHiddenOrHasHiddenAncestor)
    }
    search.stringValue = "Translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    (search.currentEditor() as! NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:)))
    precondition(controller.isTranslationMode && button.isHiddenOrHasHiddenAncestor)
    print("PASS: Use Result Tab button shares the action group, fits in light/dark modes, inserts all result types on click, and hides outside results")
}

@MainActor
private func checkResultActionKeyRelease(_ controller: ApplicationsViewController, search: NSTextField,
                                         hint: KeyboardHintView, window: NSWindow) {
    controller.resetSearch()
    search.stringValue = "2+2"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let editor = search.currentEditor() as! NSTextView
    let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                               context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
    let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                             context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
    hint.handleKeyEvent(down)
    for _ in 0..<2 { editor.doCommand(by: #selector(NSResponder.insertTab(_:))) }
    precondition(search.stringValue == "2+2" && hint.isKeyPressed)
    hint.handleKeyEvent(up)
    precondition(search.stringValue == "4" && !hint.isKeyPressed)
    hint.handleKeyEvent(up)
    precondition(search.stringValue == "4", "One Tab press must insert only once")
    hint.handleKeyEvent(down)
    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    hint.handleKeyEvent(up)
    precondition(search.stringValue == "4", "Losing focus must cancel the Tab action")
    print("PASS: Use Result responds once on Tab release, preserves pressed feedback, and cancels on focus loss")
}

@MainActor
private func checkResultActionLayout(_ view: NSView, name: String) {
    Appearance.revealLauncher(height: LauncherDisplayMode.calculator.height, on: view, duration: 0) {}
    view.layoutSubtreeIfNeeded()
    let views = calculatorDescendants(of: view)
    let actions = views.compactMap { $0 as? ActionGroupView }.first!
    let targetFrame = NSRect(x: actions.bounds.maxX - actions.targetWidth, y: 0,
                             width: actions.targetWidth, height: actions.bounds.height)
    for button in calculatorDescendants(of: actions).compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
        precondition(targetFrame.contains(actions.convert(button.bounds, from: button)),
                     "The resize target must fit the updated action buttons: \(button.accessibilityLabel() ?? "") (\(name)); button: \(actions.convert(button.bounds, from: button)); target: \(targetFrame)")
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    for button in calculatorDescendants(of: actions).compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
        let frame = actions.convert(button.bounds, from: button)
        precondition(actions.surface.frame.contains(frame),
                     "Action button must fit in the glass: \(button.accessibilityLabel() ?? "") (\(name)); button: \(frame); glass: \(actions.surface.frame); displayed/target: \(actions.displayedWidth)/\(actions.targetWidth)")
    }
    guard let directory = ProcessInfo.processInfo.environment["FLINT_CALCULATOR_PREVIEW_DIR"] else { return }
    let bounds = NSRect(x: 0, y: 0, width: view.bounds.width, height: LauncherDisplayMode.calculator.height)
    let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds)!
    view.cacheDisplay(in: bounds, to: bitmap)
    try! bitmap.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("use-result-\(name).png"))
}

@MainActor
private func checkResultInsertion() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let search = calculatorDescendants(of: controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    var dismissed = false
    controller.onDismiss = { dismissed = true }
    let clipboardChanges = NSPasteboard.general.changeCount
    let left = #selector(NSResponder.moveLeft(_:))
    let right = #selector(NSResponder.moveRight(_:))
    let up = #selector(NSResponder.moveUp(_:))
    let cases: [(String, [Selector], String)] = [
        ("2+2", [], "4"), ("1/3", [], "0.3333333333"), ("-3-2", [], "-5"),
        ("123.456+0", [left], "123.46"), ("12345+0", [left, left], "1.23E+4"),
        ("2+2", [up], "4"),
        ("1710513000", [], "2024-03-15T14:30:00Z"),
        ("1710513000123", [], "2024-03-15T14:30:00.123Z"),
        ("2024-03-15T14:30:00.123Z", [], "1710513000"),
        ("2024-03-15T14:30:00.123Z", [right], "1710513000123"),
        ("0xff", [], "255"), ("0d255", [], "0xFF"),
        ("0xff", [right, right], "0b11111111"), ("0d255", [up], "0xFF"),
        ("#ff0000", [], "rgb(255 0 0)"), ("#ff0000", [right], "hsl(0 100% 50%)"),
        ("rgb(255 0 0 / 50%)", [up], "#ff000080")
    ]
    for (query, commands, expected) in cases {
        controller.resetSearch()
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        let editor = search.currentEditor() as! NSTextView
        for command in commands { editor.doCommand(by: command) }
        editor.setSelectedRange(NSRange(location: 0, length: 1))
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition(search.stringValue == expected, "Tab for '\(query)' inserted '\(search.stringValue)', expected '\(expected)'")
        precondition(window.firstResponder === editor && search.currentEditor() === editor)
        precondition(editor.selectedRange() == NSRange(location: expected.utf16.count, length: 0))
        precondition(!dismissed && NSPasteboard.general.changeCount == clipboardChanges)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        precondition(search.stringValue == query && !dismissed, "Escape must restore the original input")
        precondition(editor.selectedRange() == NSRange(location: query.utf16.count, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition(search.stringValue == expected, "Restoring input must retain precision, format, unit, and editing mode")
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        precondition(search.stringValue == query && !dismissed)
    }
    controller.resetSearch()
    search.stringValue = "2+2"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let editor = search.currentEditor() as! NSTextView
    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    editor.insertText("*3", replacementRange: NSRange(location: NSNotFound, length: 0))
    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    precondition(search.stringValue == "12", "Typing after Tab must continue from the inserted result")
    for query in ["Finder", "3+", "#zzzz"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        precondition(search.stringValue == query && window.firstResponder === editor)
    }
    search.stringValue = "Translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    precondition(controller.isTranslationMode && search.stringValue.isEmpty)
    let translationEditor = search.currentEditor() as! NSTextView
    translationEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    precondition(search.stringValue.isEmpty && window.firstResponder === translationEditor)
    print("PASS: Tab inserts arithmetic, rounded, scientific, timestamp, base, and color results; focus, caret, clipboard, and chaining are preserved")
    print("PASS: Tab keeps normal search focused and retains translation entry and translation-mode behavior")
}

@MainActor
private func checkResultRestoration() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    controller.resetSearch()
    let views = calculatorDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let back = views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("restorePreviousInput") }!
    let hint = calculatorDescendants(of: back).compactMap { $0 as? KeyboardHintView }.first!
    let editor = search.currentEditor() as! NSTextView
    let tab = #selector(NSResponder.insertTab(_:))
    let escape = #selector(NSResponder.cancelOperation(_:))
    var dismissed = false
    controller.onDismiss = { dismissed = true }
    let setQuery: (String) -> Void = { query in
        editor.insertText(query, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }
    setQuery(" 2+2 ")
    editor.doCommand(by: tab)
    precondition(search.stringValue == "4" && !back.isHiddenOrHasHiddenAncestor && hint.hint == .escape)
    setQuery("4*3")
    editor.doCommand(by: tab)
    precondition(search.stringValue == "12")
    let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                               context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    hint.handleKeyEvent(down)
    for _ in 0..<2 { editor.doCommand(by: escape) }
    precondition(search.stringValue == "12" && hint.isKeyPressed)
    hint.handleKeyEvent(up)
    hint.handleKeyEvent(up)
    precondition(search.stringValue == "4*3" && !dismissed)
    hint.handleKeyEvent(down)
    editor.doCommand(by: escape)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    hint.handleKeyEvent(up)
    precondition(search.stringValue == "4*3", "Focus loss must cancel Back")
    setQuery("1/3")
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        checkResultActionLayout(controller.view, name: "back-\(name)")
    }
    back.performClick(nil)
    precondition(search.stringValue == " 2+2 " && back.isHiddenOrHasHiddenAncestor && !dismissed)
    precondition(window.firstResponder === editor && editor.selectedRange().location == " 2+2 ".utf16.count)
    editor.doCommand(by: escape)
    precondition(dismissed, "Escape must dismiss when history is empty")
    dismissed = false
    editor.doCommand(by: tab)
    controller.resetSearch()
    editor.doCommand(by: escape)
    precondition(dismissed && back.isHiddenOrHasHiddenAncestor, "Reopening must clear result history")
    dismissed = false
    setQuery("rgb(255 0 0)")
    editor.doCommand(by: #selector(NSResponder.moveRight(_:)))
    editor.doCommand(by: tab)
    precondition(search.stringValue == "rgb(255 0 0)" && back.isHiddenOrHasHiddenAncestor)
    editor.doCommand(by: escape)
    precondition(dismissed, "An unchanged result must not add history")
    dismissed = false
    controller.resetSearch()
    setQuery("2+2")
    editor.doCommand(by: tab)
    setQuery("Translate")
    editor.doCommand(by: tab)
    precondition(controller.isTranslationMode && back.isHiddenOrHasHiddenAncestor)
    (search.currentEditor() as! NSTextView).doCommand(by: escape)
    precondition(!controller.isTranslationMode && search.stringValue.isEmpty && !dismissed)
    (search.currentEditor() as! NSTextView).doCommand(by: escape)
    precondition(dismissed, "Translation must clear result history and retain its Escape behavior")
    print("PASS: Escape/Back restores chained inputs and exact whitespace, retains output choices, cancels on focus loss, and resets for reopening/translation")
}

@MainActor
private func calculatorDescendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + calculatorDescendants(of: $0) }
}

@MainActor
func checkTimestampIntegration() {
    let controller = ApplicationsViewController()
    _ = controller.view
    let views = calculatorDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? CalculatorResultView }.first!
    let copy = views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("openSelectedApplication") }!
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    var dismissed = false
    controller.onDismiss = { dismissed = true }
    let query = "2024-03-15T14:30:00Z"
    search.stringValue = query
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    controller.view.layoutSubtreeIfNeeded()
    precondition(controller.displayMode == .calculator && !result.isHidden && copy.isEnabled)
    precondition(copy.accessibilityLabel() == "Copy Answer")
    let labels = calculatorDescendants(of: result).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == query })
    precondition(labels.contains { $0.stringValue == "1710513000" })
    let hint = labels.first { $0.stringValue == TimestampCalculation.evaluate(query)!.localTimeHint() }!
    let input = labels.first { $0.stringValue == query }!
    precondition(!hint.isHidden && hint.superview === input.superview && hint.frame.minY < input.frame.minY)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "1710513000" && dismissed)
    dismissed = false
    search.stringValue = "2024-02-30T00:00:00Z"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(controller.displayMode == .results && result.isHidden && !copy.isEnabled)
    precondition(pasteboard.string(forType: .string) == "1710513000" && !dismissed)
    search.stringValue = "2+2"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(hint.isHidden && input.font?.pointSize == 36 && input.stringValue == "2 + 2")
    search.stringValue = "2024-03-15T14:30:00.123456789Z"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "1710513000")
    precondition(hint.stringValue == TimestampCalculation.evaluate(search.stringValue)!.localTimeHint())
    for (seconds, zulu) in [("1710513000", "2024-03-15T14:30:00Z"),
                            ("0", "1970-01-01T00:00:00Z"),
                            ("1", "1970-01-01T00:00:01Z"),
                            ("1710513000123", "2024-03-15T14:30:00.123Z"),
                            ("1 ms", "1970-01-01T00:00:00.001Z")] {
        checkReverseTimestamp(controller, search: search, query: seconds, expected: zulu, pasteboard: pasteboard)
    }
    search.stringValue = query
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(!hint.isHidden)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "1710513000")
    checkTimestampUnitLabel(controller, search: search, pasteboard: pasteboard)
    controller.resetSearch()
    precondition(controller.displayMode == .collapsed && result.isHidden && !copy.isEnabled)
    print("PASS: timestamps convert in seconds and milliseconds, with unit selection, exact copying, and local hints under Zulu")
}

@MainActor
private func checkReverseTimestamp(_ controller: ApplicationsViewController, search: NSTextField,
                                    query: String, expected: String, pasteboard: NSPasteboard) {
    search.stringValue = query
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    controller.view.layoutSubtreeIfNeeded()
    precondition(controller.displayMode == .calculator)
    let result = calculatorDescendants(of: controller.view).compactMap { $0 as? CalculatorResultView }.first!
    let labels = calculatorDescendants(of: result).compactMap { $0 as? NSTextField }
    let zulu = labels.first { $0.stringValue == expected }!
    let local = labels.first { !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == TimestampCalculation.evaluate(query)!.localTimeHint() }!
    precondition(!local.isHidden && local.superview === zulu.superview && local.frame.minY < zulu.frame.minY)
    let calculation = TimestampCalculation.evaluate(query)!
    precondition(labels.contains { $0.stringValue == calculation.unixValue })
    precondition(labels.contains { $0.stringValue == calculation.unit.title })
    precondition(zulu.font!.pointSize <= 18 && zulu.frame.width > 250)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == expected)
}

@MainActor
private func checkTimestampUnitLabel(_ controller: ApplicationsViewController, search: NSTextField,
                                      pasteboard: NSPasteboard) {
    search.stringValue = "2024-03-15T14:30:00.123456789Z"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let views = calculatorDescendants(of: controller.view)
    let unit = views.compactMap { $0 as? NSTextField }.first { !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == "Unix seconds" }!
    precondition(!unit.isHidden && !unit.isEditable)
    precondition(!views.contains { $0 is NSSegmentedControl })
    let editor = NSTextView()
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(unit.stringValue == "Unix milliseconds")
    controller.view.layoutSubtreeIfNeeded()
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "1710513000123")
    let labels = calculatorDescendants(of: controller.view).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == "1710513000123" && !$0.isHiddenOrHasHiddenAncestor })
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(unit.stringValue == "Unix seconds")
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "1710513000")
    search.stringValue = "2+2"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(unit.isHidden)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "4")
}

@MainActor
func checkTimestampKeyboardSwitching() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let search = calculatorDescendants(of: controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let query = "2024-03-15T14:30:00.123Z"
    search.stringValue = query
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let views = calculatorDescendants(of: controller.view)
    let hint = views.compactMap { $0 as? KeyboardHintView }.first { $0.label == "ms" }!
    let unit = views.compactMap { $0 as? NSTextField }.first { !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == "Unix seconds" }!
    precondition(!hint.isHiddenOrHasHiddenAncestor && !unit.isHidden && hint.hint == .rightArrow)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let editor = NSTextView()
    let steps: [(Selector, String, String)] = [
        (#selector(NSResponder.moveRight(_:)), "Unix milliseconds", "1710513000123"),
        (#selector(NSResponder.moveRight(_:)), "Unix milliseconds", "1710513000123"),
        (#selector(NSResponder.moveLeft(_:)), "Unix seconds", "1710513000"),
        (#selector(NSResponder.moveBackward(_:)), "Unix seconds", "1710513000"),
        (#selector(NSResponder.moveForward(_:)), "Unix milliseconds", "1710513000123")
    ]
    for (selector, title, expected) in steps {
        precondition(controller.control(search, textView: editor, doCommandBy: selector))
        precondition(unit.stringValue == title && search.stringValue == query)
        let showsSeconds = title == "Unix seconds"
        precondition(hint.label == (showsSeconds ? "ms" : "s"))
        precondition(hint.hint == (showsSeconds ? .rightArrow : .leftArrow))
        controller.copyCalculationAnswer(to: pasteboard)
        precondition(pasteboard.string(forType: .string) == expected)
    }
    for selector in [#selector(NSResponder.moveWordLeft(_:)), #selector(NSResponder.moveRightAndModifySelection(_:))] {
        precondition(!controller.control(search, textView: editor, doCommandBy: selector))
        precondition(unit.stringValue == "Unix milliseconds")
    }
    for input in ["Finder", "1710513000", "1710513000123", "2024-02-30T00:00:00Z", ""] {
        search.stringValue = input
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(hint.isHiddenOrHasHiddenAncestor)
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }
    search.stringValue = "123.456+0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(hint.isHiddenOrHasHiddenAncestor)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "123.46")
    print("PASS: Left selects seconds, Right selects milliseconds, copy follows the unit, and other modes retain their arrow behavior")
}

@MainActor
func checkCalculatorToSearchTransitions() {
    let suite = "FlintTransitionChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = LauncherPreferences(defaults: defaults)
    preferences.switchToABC = false
    let launcher = LauncherWindowController(preferences: preferences, keepsOpenOnFocusLoss: true)
    launcher.showLauncher()
    let window = launcher.window!
    defer { window.orderOut(nil) }
    let controller = window.contentViewController as! ApplicationsViewController
    let root = controller.view
    let views = calculatorDescendants(of: root)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let scroll = views.compactMap { $0 as? NSScrollView }.first { $0.documentView is NSTableView }!
    let results = scroll.superview!.superview!
    let top = window.frame.maxY
    let steps = [("1710513000", 24), ("2024-03-15T14:30:00Z", 24), ("2024-02-30T00:00:00Z", 24), ("", 24),
                 ("1", 24), ("1+", 24), ("1+1", 24), ("", 24), ("a", 24), ("", 24),
                 ("2+2", 2), ("", 2), ("eject", 24), ("3f", 24), ("3", 24),
                 ("3+2f", 24), ("3+2", 24), ("3+", 24), ("3+2", 24), ("3", 24)]
    for (query, samples) in steps {
        let previousMode = controller.displayMode
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        if previousMode != controller.displayMode, previousMode != .collapsed, controller.displayMode != .collapsed {
            checkModeResize(root: root, from: previousMode.height, to: controller.displayMode.height)
        }
        checkStationaryResults(root: root, views: [results, scroll.superview!, scroll],
                               window: window, top: top, query: query, samples: samples)
        if samples == 24 { precondition(window.frame.height == controller.displayMode.height) }
    }
    print("PASS: number → delete → letter keeps results below the search bar throughout animation")
}

@MainActor
private func checkModeResize(root: NSView, from initialHeight: CGFloat, to targetHeight: CGFloat) {
    let settings = calculatorDescendants(of: root).compactMap { $0 as? NSButton }
        .first { $0.accessibilityLabel() == "Settings" }!
    let footer = settings.superview!.superview!
    let viewport = root.subviews[0]
    var sawIntermediateHeight = false
    for _ in 0..<24 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.015))
        guard let renderedViewport = viewport.layer?.presentation(),
              let renderedFooter = footer.layer?.presentation(),
              let renderedRoot = root.layer?.presentation() else { continue }
        let height = renderedViewport.bounds.height
        if height > min(initialHeight, targetHeight) + 2 && height < max(initialHeight, targetHeight) - 2 {
            sawIntermediateHeight = true
        }
        let footerFrame = renderedRoot.convert(renderedFooter.bounds, from: renderedFooter)
        precondition(abs(footerFrame.maxY - height) < 2,
                     "Footer jumped during resize: footer \(footerFrame.maxY), panel \(height)")
    }
    precondition(sawIntermediateHeight || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                 "Search ↔ calculator skipped the panel resize animation")
    print("PASS: search ↔ calculator animates the panel and footer together")
}

@MainActor
private func checkStationaryResults(root: NSView, views: [NSView], window: NSWindow,
                                    top: CGFloat, query: String, samples: Int) {
    for _ in 0..<samples {
        RunLoop.current.run(until: Date().addingTimeInterval(0.015))
        precondition(abs(window.frame.maxY - top) < 0.5, "The launcher top moved for query '\(query)'")
        for view in views {
            guard !query.isEmpty, !view.isHidden, let layer = view.layer, let rendered = layer.presentation(),
                  let rootLayer = root.layer, let renderedRoot = rootLayer.presentation() else { continue }
            let expected = rootLayer.convert(layer.bounds, from: layer)
            let actual = renderedRoot.convert(rendered.bounds, from: rendered)
            precondition(abs(actual.minY - expected.minY) < 1,
                         "Results moved above search for '\(query)': rendered \(actual), expected \(expected)")
        }
    }
}
