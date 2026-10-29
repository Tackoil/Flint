import AppKit

@MainActor
func checkColorConversionIntegration() {
    let controller = ApplicationsViewController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 232),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let search = colorDescendants(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let editor = NSTextView()
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let left = #selector(NSResponder.moveLeft(_:))
    let right = #selector(NSResponder.moveRight(_:))
    search.stringValue = "#ff636380"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(controller.displayMode == .calculator)
    let colorView = colorDescendants(controller.view).compactMap { $0 as? ColorResultView }.first!
    precondition(!colorView.isHiddenOrHasHiddenAncestor)
    let swatch = colorDescendants(colorView).compactMap { $0 as? ColorSwatchView }.first!
    precondition(abs(swatch.color.alphaComponent - 128.0 / 255) < 0.00001)
    let copy = colorDescendants(controller.view).compactMap { $0 as? NSButton }
        .first { $0.accessibilityLabel() == "Copy Color" }!
    precondition(copy.isEnabled)
    checkColorStripLayout(colorView)
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "rgb(255 99 99 / 0.50196)")
    for format in ["HSL", "HWB", "LAB", "LCH", "OKLAB", "OKLCH", "HEX", "RGB"] {
        precondition(controller.control(search, textView: editor, doCommandBy: right))
        let selected = colorDescendants(colorView).compactMap { $0 as? ColorFormatPreviewView }.first { $0.isPrimary }!
        let labels = colorDescendants(selected).compactMap { $0 as? NSTextField }
        precondition(labels.contains { $0.stringValue == format })
        let output = labels.first { $0.toolTip == $0.stringValue }!.stringValue
        controller.copyCalculationAnswer(to: pasteboard)
        precondition(pasteboard.string(forType: .string) == output)
        precondition(search.stringValue == "#ff636380")
    }
    precondition(controller.control(search, textView: editor, doCommandBy: left))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "#ff636380")
    for selector in [#selector(NSResponder.moveWordLeft(_:)), #selector(NSResponder.moveRightAndModifySelection(_:))] {
        precondition(!controller.control(search, textView: editor, doCommandBy: selector))
    }
    checkColorTransitions(controller, search: search, colorView: colorView, editor: editor, pasteboard: pasteboard)
    checkColorEditingMode(controller, search: search, editor: editor, pasteboard: pasteboard)
    checkColorOutputAnimation(controller, search: search, editor: editor, window: window)
    renderColorPreviews(controller, search: search, window: window)
    print("PASS: all eight color formats, bidirectional arrow cycling, alpha swatch, copying, and search/calculator transitions")
}

@MainActor
private func checkColorStripLayout(_ colorView: ColorResultView) {
    colorView.window?.contentView?.layoutSubtreeIfNeeded()
    let views = colorDescendants(colorView)
    let swatch = views.compactMap { $0 as? ColorSwatchView }.first!
    let strip = views.compactMap { $0 as? ColorPreviewStripView }.first!
    let outputs = views.compactMap { $0 as? ColorFormatPreviewView }
        .filter { !$0.isAccessibilityHidden() }.sorted { $0.frame.minX < $1.frame.minX }
    precondition(outputs.map(\.format) == [.rgb, .hsl, .hwb, .lab, .lch, .oklab, .oklch, .hex])
    precondition(swatch.frame.size == NSSize(width: 48, height: 48))
    precondition(abs(swatch.frame.height - outputs[0].frame.height) < 10)
    precondition(outputs[0].alphaValue == 1 && outputs.dropFirst().allSatisfy { $0.alphaValue == 0.4 })
    let current = strip.convert(outputs[0].bounds, from: outputs[0])
    let next = strip.convert(outputs[1].bounds, from: outputs[1])
    precondition(current.minX == 0 && next.minX >= current.maxX + 31)
    precondition(next.minX < strip.bounds.width, "The next output must be visible to the right")
    let last = strip.convert(outputs.last!.bounds, from: outputs.last!)
    precondition(last.maxX > strip.bounds.width, "Upcoming outputs must fill the entire strip")
    precondition(colorView.convert(strip.bounds, from: strip).maxX == colorView.bounds.maxX)
    let fade = strip.layer!.mask as! CAGradientLayer
    precondition(fade.frame == strip.bounds && fade.startPoint.x == 0 && fade.endPoint.x == 1)
    precondition(fade.locations!.first == 0 && fade.locations!.last == 1)
    print("PASS: text-height color swatch, dimmed upcoming formats, full-width preview strip, and right-edge fade")
}

@MainActor
private func checkColorTransitions(_ controller: ApplicationsViewController, search: NSTextField,
                                   colorView: ColorResultView, editor: NSTextView, pasteboard: NSPasteboard) {
    for query in ["oklch(70% .4 30 / .5)", "#abc", "rgb(0 0 0)"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(!colorView.isHiddenOrHasHiddenAncestor)
        controller.copyCalculationAnswer(to: pasteboard)
        precondition(pasteboard.string(forType: .string)?.hasPrefix("#") == true)
    }
    for query in ["rgb(255 0", "Finder", "2+3", "2024-03-15T14:30:00Z", ""] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(colorView.isHiddenOrHasHiddenAncestor)
    }
    controller.resetSearch()
    search.stringValue = "#abc"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "rgb(170 187 204)")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
}

@MainActor
private func checkColorEditingMode(_ controller: ApplicationsViewController, search: NSTextField,
                                   editor: NSTextView, pasteboard: NSPasteboard) {
    controller.resetSearch()
    search.stringValue = "#ff6363"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let views = colorDescendants(controller.view)
    let button = views.compactMap { $0 as? NSButton }
        .first { $0.action == NSSelectorFromString("toggleColorSwitchingMode") }!
    let previous = views.compactMap { $0 as? KeyboardHintView }
        .first { $0.hint == .leftArrow && $0.label == "HEX" }!
    let next = views.compactMap { $0 as? KeyboardHintView }
        .first { $0.hint == .rightArrow && $0.label == "HSL" }!
    precondition(!previous.isHiddenOrHasHiddenAncestor && !next.isHiddenOrHasHiddenAncestor)
    precondition(button.accessibilityLabel() == "Edit color" && !button.acceptsFirstResponder)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(previous.label == "RGB" && next.label == "HWB")
    controller.copyCalculationAnswer(to: pasteboard)
    let selectedOutput = pasteboard.string(forType: .string)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
    precondition(button.accessibilityLabel() == "Switch format")
    precondition(previous.isHiddenOrHasHiddenAncestor && next.isHiddenOrHasHiddenAncestor)
    precondition(controller.displayMode == .calculator)
    precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    controller.copyCalculationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == selectedOutput)
    for query in ["#ff636", "#ff636380"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    }
    precondition(button.accessibilityLabel() == "Switch format")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    precondition(!previous.isHiddenOrHasHiddenAncestor && !next.isHiddenOrHasHiddenAncestor)
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Switch format")
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Edit color")
    controller.resetSearch()
    search.stringValue = "#abc"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(button.accessibilityLabel() == "Edit color")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(previous.label == "OKLCH" && next.label == "RGB")
    for query in ["Finder", "2+3", "2024-03-15T14:30:00Z"] {
        search.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(button.isHidden && previous.isHiddenOrHasHiddenAncestor && next.isHiddenOrHasHiddenAncestor)
    }
    print("PASS: color editing with Up/Down or buttons, retained output and editing mode, reset on reopen, and adjacent format hints")
}

@MainActor
private func checkColorOutputAnimation(_ controller: ApplicationsViewController, search: NSTextField,
                                      editor: NSTextView, window: NSWindow) {
    controller.resetSearch()
    search.stringValue = "#66ccff"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    window.contentView!.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let views = colorDescendants(controller.view)
    let color = views.compactMap { $0 as? ColorResultView }.first!
    let strip = views.compactMap { $0 as? ColorPreviewStripView }.first!
    let swatch = views.compactMap { $0 as? ColorSwatchView }.first!
    let swatchFrame = swatch.frame
    let oldPrimary = views.compactMap { $0 as? ColorFormatPreviewView }.first { $0.isPrimary }!
    let right = #selector(NSResponder.moveRight(_:))
    let left = #selector(NSResponder.moveLeft(_:))
    precondition(controller.control(search, textView: editor, doCommandBy: right))
    let primary = colorDescendants(color).compactMap { $0 as? ColorFormatPreviewView }.first { $0.isPrimary }!
    precondition(primary.format == .hsl)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(primary.layer!.animation(forKey: "colorOutputPosition") == nil)
        return
    }
    let forward = primary.layer!.animation(forKey: "colorOutputPosition") as! CABasicAnimation
    precondition((forward.fromValue as! CGPoint).x > (forward.toValue as! CGPoint).x)
    precondition(primary.layer!.animation(forKey: "colorOutputOpacity") != nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.06))
    let displayed = oldPrimary.layer!.presentation()!
    let position = strip.layer!.convert(displayed.position, from: displayed.superlayer!)
    precondition(controller.control(search, textView: editor, doCommandBy: left))
    let reverse = oldPrimary.layer!.animation(forKey: "colorOutputPosition") as! CABasicAnimation
    let resumed = strip.layer!.convert(reverse.fromValue as! CGPoint, from: oldPrimary.layer!.superlayer!)
    precondition(abs(position.x - resumed.x) < 1, "Reversing must continue from the visible position")
    precondition(oldPrimary.isPrimary && oldPrimary.format == .rgb)
    precondition((reverse.fromValue as! CGPoint).x < (reverse.toValue as! CGPoint).x)
    precondition(swatch.frame == swatchFrame, "Switching formats must keep the swatch stationary")
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    precondition(oldPrimary.layer!.animation(forKey: "colorOutputPosition") == nil)
    precondition(abs(strip.convert(oldPrimary.bounds, from: oldPrimary).minX) < 1)
    // HEX to OKLCH crosses the beginning of the format cycle in the same direction.
    precondition(controller.control(search, textView: editor, doCommandBy: left))
    precondition(controller.control(search, textView: editor, doCommandBy: left))
    let wrapped = colorDescendants(color).compactMap { $0 as? ColorFormatPreviewView }.first { $0.isPrimary }!
    precondition(wrapped.format == .oklch && wrapped.layer!.animation(forKey: "colorOutputPosition") != nil)
    search.stringValue = "#ff6363"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(wrapped.layer!.animation(forKey: "colorOutputPosition") == nil)
    print("PASS: directional color sliding, emphasis fades, seamless reversal, cycle wrapping, and stationary swatch")
}

@MainActor
private func renderColorPreviews(_ controller: ApplicationsViewController, search: NSTextField, window: NSWindow) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_COLOR_PREVIEW_DIR"] else { return }
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        search.stringValue = "rgb(255 99 99 / 50%)"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        Appearance.revealLauncher(height: 232, on: controller.view, duration: 0) {}
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)!
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        let data = bitmap.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("color-\(name).png"))
    }
}

@MainActor
private func colorDescendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + colorDescendants($0) }
}
