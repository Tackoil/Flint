import AppKit

@MainActor
func checkNumberBaseIntegration() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 232),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = numberBaseDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? NumberBaseResultView }.first!
    let editor = NSTextView()
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    search.stringValue = "0xff"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(controller.displayMode == .calculator && !result.isHiddenOrHasHiddenAncestor)
    let copy = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Copy Number" }!
    precondition(copy.isEnabled && copy.action == NSSelectorFromString("openSelectedApplication"))
    let rows = numberBaseDescendants(result).compactMap { $0 as? NumberBaseRowView }
    precondition(rows.map(\.format) == [.decimal, .hex, .binary])
    for (format, expected) in [(NumberBaseConversion.Format.decimal, "255"), (.hex, "0xFF"),
                               (.binary, "0b11111111"), (.decimal, "255")] {
        precondition(rows.first { $0.isSelected }?.format == format)
        precondition(rows.filter { $0.alphaValue == 1 }.count == 1)
        var dismissed = false
        controller.onDismiss = { dismissed = true }
        controller.copyCalculationAnswer(to: pasteboard)
        precondition(pasteboard.string(forType: .string) == expected && dismissed)
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        precondition(search.stringValue == "0xff")
    }
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    checkNumberBaseEditing(controller, search: search, editor: editor, pasteboard: pasteboard)
    checkNumberBaseTransitions(controller, search: search, result: result, editor: editor)
    checkNumberBaseLayout(controller, search: search, window: window)
    print("PASS: number base defaults, all formats, arrow wrapping, clean copying, editing, transitions, and full-width layout")
}

@MainActor
private func checkNumberBaseEditing(_ controller: ApplicationsViewController, search: NSTextField,
                                    editor: NSTextView, pasteboard: NSPasteboard) {
    let views = numberBaseDescendants(controller.view)
    let button = views.compactMap { $0 as? NSButton }
        .first { $0.action == NSSelectorFromString("toggleNumberBaseSwitchingMode") }!
    precondition(button.accessibilityLabel() == "Edit number" && !button.acceptsFirstResponder)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
    precondition(button.accessibilityLabel() == "Switch base")
    for query in ["0x", "0xff"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "255")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    precondition(button.accessibilityLabel() == "Edit number")
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Switch base")
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Edit number")
    for selector in [#selector(NSResponder.moveWordLeft(_:)), #selector(NSResponder.moveRightAndModifySelection(_:))] {
        precondition(!controller.control(search, textView: editor, doCommandBy: selector))
    }
    let hints = views.compactMap { $0 as? KeyboardHintView }.filter { !$0.isHiddenOrHasHiddenAncestor }
    precondition(hints.contains { $0.hint == .leftArrow && $0.label == "BIN" })
    precondition(hints.contains { $0.hint == .rightArrow && $0.label == "HEX" })
}

@MainActor
private func checkNumberBaseTransitions(_ controller: ApplicationsViewController, search: NSTextField,
                                       result: NumberBaseResultView, editor: NSTextView) {
    for query in ["0b102", "0x", "Finder", "2+3", "255", "#ff6600", ""] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(result.isHiddenOrHasHiddenAncestor)
        let button = numberBaseDescendants(controller.view).compactMap { $0 as? NSButton }
            .first { $0.action == NSSelectorFromString("toggleNumberBaseSwitchingMode") }!
        precondition(button.isHiddenOrHasHiddenAncestor)
    }
    controller.resetSearch()
    search.stringValue = "0d255"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(numberBaseDescendants(result).compactMap { $0 as? NumberBaseRowView }.first { $0.isSelected }?.format == .hex)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
    controller.resetSearch()
    search.stringValue = "0b101010"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(numberBaseDescendants(result).compactMap { $0 as? NumberBaseRowView }.first { $0.isSelected }?.format == .binary)
}

@MainActor
private func checkNumberBaseLayout(_ controller: ApplicationsViewController, search: NSTextField, window: NSWindow) {
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        for (example, query) in [("short", "0xff"), ("full", "-0xffffffffffffffff")] {
            controller.resetSearch()
            search.stringValue = query
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            Appearance.revealLauncher(height: 232, on: controller.view, duration: 0) {}
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let result = numberBaseDescendants(controller.view).compactMap { $0 as? NumberBaseResultView }.first!
            for row in numberBaseDescendants(result).compactMap({ $0 as? NumberBaseRowView }) {
                precondition(result.bounds.contains(result.convert(row.bounds, from: row)))
                precondition(abs(row.bounds.width - (result.bounds.width - 80)) < 1,
                             "Every output row must fill the available width")
                precondition(abs(result.convert(row.bounds, from: row).minX - 40) < 1,
                             "Output rows must share the same leading edge")
                let value = row.subviews.compactMap { $0 as? NSTextField }.first { $0.toolTip != nil }!
                let size = (value.stringValue as NSString).size(withAttributes: [.font: value.font!])
                let drawingWidth = value.cell!.drawingRect(forBounds: value.bounds).width
                precondition(size.width <= drawingWidth, "Full values must fit without truncation")
                precondition(value.font!.pointSize >= 11)
            }
            renderNumberBasePreview(controller.view, name: "number-base-\(example)-\(name)")
        }
    }
}

@MainActor
private func renderNumberBasePreview(_ view: NSView, name: String) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_NUMBER_BASE_PREVIEW_DIR"] else { return }
    let bounds = NSRect(x: 0, y: 0, width: view.bounds.width, height: LauncherDisplayMode.calculator.height)
    let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds)!
    view.cacheDisplay(in: bounds, to: bitmap)
    let data = bitmap.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
}

@MainActor
private func numberBaseDescendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + numberBaseDescendants($0) }
}
