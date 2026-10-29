import AppKit

@MainActor
func checkNumericRoundingIntegration() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = roundingDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let editor = NSTextView()
    search.stringValue = "123.456+0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let answer = roundingDescendants(of: controller.view).compactMap { $0 as? NSTextField }
        .first { $0.stringValue == "123.456" }!
    let steps: [(Selector, String)] = [
        (#selector(NSResponder.moveLeft(_:)), "123.46"),
        (#selector(NSResponder.moveLeft(_:)), "123.5"),
        (#selector(NSResponder.moveRight(_:)), "123.46")
    ]
    for (selector, expected) in steps {
        precondition(controller.control(search, textView: editor, doCommandBy: selector))
        precondition(answer.stringValue == expected + "…" && search.stringValue == "123.456+0")
        controller.copyCalculationAnswer(to: pasteboard)
        precondition(pasteboard.string(forType: .string) == expected)
    }
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(answer.stringValue == "123.46…", "Refreshing the same expression must retain rounding")
    for selector in [#selector(NSResponder.moveWordLeft(_:)), #selector(NSResponder.moveLeftAndModifySelection(_:))] {
        precondition(!controller.control(search, textView: editor, doCommandBy: selector))
    }
    search.stringValue = "123.456+1"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(answer.stringValue == "124.456", "Editing the expression must reset rounding")
    search.stringValue = "12345+0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    for _ in 0..<2 {
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    }
    precondition(answer.stringValue == "1.23E+4")
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "1.23E+4")
    for _ in 0..<2 {
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "12345")
    checkFractionalDigitControls(controller, search: search, editor: editor, answer: answer, pasteboard: pasteboard)
    for query in ["Finder", "1710513000"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "2024-03-15T14:30:00Z")
    print("PASS: decimal-place controls, continuation markers, clean copying, and Unix input/search cursor movement")
}

@MainActor
private func checkFractionalDigitControls(_ controller: ApplicationsViewController, search: NSTextField,
                                          editor: NSTextView, answer: NSTextField, pasteboard: NSPasteboard) {
    let labels = roundingDescendants(of: controller.view).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == "0 digits after decimal" })
    search.stringValue = "3^(-1/2)"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(answer.stringValue == "0.5773502692…")
    precondition(labels.contains { $0.stringValue == "10 digits after decimal" })
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(answer.stringValue == "0.57735026919…")
    precondition(labels.contains { $0.stringValue == "11 digits after decimal" })
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "0.57735026919")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    controller.view.layoutSubtreeIfNeeded()
    precondition(answer.stringValue == "0.577350269190…")
    precondition(answer.font?.pointSize == 36 && answer.lineBreakMode == .byTruncatingMiddle)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "0.577350269190")
    search.stringValue = "12345+0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(labels.contains { $0.stringValue == "1 digit before decimal" })
}

@MainActor
private func roundingDescendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + roundingDescendants(of: $0) }
}

@MainActor
func checkRoundingModeSwitches() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = roundingDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let button = views.compactMap { $0 as? NSButton }
        .first { $0.action == NSSelectorFromString("toggleRoundingMode") }!
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let editor = NSTextView()
    search.stringValue = "123.456+0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(!button.isHidden && !button.acceptsFirstResponder)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
    precondition(button.accessibilityLabel() == "Round result" && controller.displayMode == .calculator)
    precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "123.456", "Leaving rounding must restore default copying")
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Edit expression")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "123.456")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    button.performClick(nil)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "123.456", "The Edit expression button must reset precision")
    checkEditingModeSurvivesInput(controller, search: search, editor: editor, button: button)
    checkDefaultPrecisionOnExit(controller, search: search, editor: editor, button: button, pasteboard: pasteboard)
    controller.resetSearch()
    search.stringValue = "123.456+0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(button.accessibilityLabel() == "Edit expression")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    for query in ["Finder", "2024-03-15T14:30:00Z"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(button.isHidden)
    }
    print("PASS: Up/button leave rounding and reset displayed/copied precision; Down resumes rounding; edits retain editing mode")
}

@MainActor
private func checkDefaultPrecisionOnExit(_ controller: ApplicationsViewController, search: NSTextField,
                                         editor: NSTextView, button: NSButton, pasteboard: NSPasteboard) {
    search.stringValue = "1/3"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    for _ in 0..<3 {
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "0.3333333333333")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "0.3333333333")
    let labels = roundingDescendants(of: controller.view).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == "0.3333333333…" })
    let precisionLabel = labels.first { $0.stringValue == "10 digits after decimal" }!
    precondition(precisionLabel.isHiddenOrHasHiddenAncestor, "Editing must hide the digit count")
    button.performClick(nil)
    precondition(!precisionLabel.isHiddenOrHasHiddenAncestor, "Rounding must restore the digit count")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    button.performClick(nil)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "0.3333333333")
}

@MainActor
private func checkEditingModeSurvivesInput(_ controller: ApplicationsViewController, search: NSTextField,
                                         editor: NSTextView, button: NSButton) {
    for query in ["123.456+1", "123.456+", "123.456+2"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    }
    precondition(button.accessibilityLabel() == "Round result")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    precondition(button.accessibilityLabel() == "Edit expression")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
}

@MainActor
func checkModeChangesOnKeyRelease() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 232),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = roundingDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let cases = [("123.456+0", "toggleRoundingMode", "Edit expression", "Round result"),
                 ("#ff6363", "toggleColorSwitchingMode", "Edit color", "Switch format")]
    for (query, action, initial, editing) in cases {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        let button = views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString(action) }!
        let hint = roundingDescendants(of: button).compactMap { $0 as? KeyboardHintView }.first!
        checkDeferredModeCommand(controller, search: search, hint: hint, keyCode: 126,
                                 selector: #selector(NSResponder.moveUp(_:)), before: initial, after: editing) {
            button.accessibilityLabel()!
        }
        checkDeferredModeCommand(controller, search: search, hint: hint, keyCode: 125,
                                 selector: #selector(NSResponder.moveDown(_:)), before: editing, after: initial) {
            button.accessibilityLabel()!
        }
        hint.handleKeyEvent(modeKeyEvent(126))
        precondition(controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:))))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        hint.handleKeyEvent(modeKeyEvent(126, type: .keyUp))
        precondition(button.accessibilityLabel() == initial, "Focus loss must cancel the pending mode change")
    }
    checkOutputChangesOnKeyRelease(controller, search: search)
    print("PASS: calculator/color modes, color formats and timestamp units change once on release; focus loss cancels pending switches")
}

@MainActor
private func checkOutputChangesOnKeyRelease(_ controller: ApplicationsViewController, search: NSTextField) {
    for (query, label, after) in [("#ff6363", "HSL", "HWB"), ("2024-03-15T14:30:00Z", "ms", "s")] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        let hint = roundingDescendants(of: controller.view).compactMap { $0 as? KeyboardHintView }
            .first { !$0.isHiddenOrHasHiddenAncestor && $0.label == label }!
        checkDeferredModeCommand(controller, search: search, hint: hint, keyCode: 124,
                                 selector: #selector(NSResponder.moveRight(_:)), before: label, after: after) {
            hint.label!
        }
        let before = hint.label
        hint.handleKeyEvent(modeKeyEvent(hint.hint == .leftArrow ? 123 : 124, type: .keyUp))
        precondition(hint.label == before, "A release without a press must not change output")
    }
}

@MainActor
private func checkDeferredModeCommand(_ controller: ApplicationsViewController, search: NSTextField,
                                      hint: KeyboardHintView, keyCode: UInt16, selector: Selector,
                                      before: String, after: String, state: () -> String) {
    let editor = NSTextView()
    hint.handleKeyEvent(modeKeyEvent(keyCode))
    precondition(controller.control(search, textView: editor, doCommandBy: selector))
    precondition(state() == before && hint.isKeyPressed, "Key down must preserve the current mode and pressed hint")
    hint.handleKeyEvent(modeKeyEvent(keyCode, isRepeat: true))
    precondition(controller.control(search, textView: editor, doCommandBy: selector))
    hint.handleKeyEvent(modeKeyEvent(53, type: .keyUp))
    precondition(state() == before && hint.isKeyPressed, "Repeats and unrelated releases must not change modes")
    hint.handleKeyEvent(modeKeyEvent(keyCode, type: .keyUp))
    precondition(state() == after && !hint.isKeyPressed, "The matching release must change the mode")
    hint.handleKeyEvent(modeKeyEvent(keyCode, type: .keyUp))
    precondition(state() == after, "Duplicate releases must not change the mode again")
}

private func modeKeyEvent(_ keyCode: UInt16, type: NSEvent.EventType = .keyDown, isRepeat: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                    context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: isRepeat, keyCode: keyCode)!
}
