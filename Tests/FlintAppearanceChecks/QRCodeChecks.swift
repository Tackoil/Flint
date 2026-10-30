import AppKit
import Vision

@MainActor
func checkQRCodeIntegration() {
    let controller = ApplicationsViewController()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.onDisplayModeChange = { [weak window, weak controller] mode in
        guard let window, let controller else { return }
        window.setContentSize(NSSize(width: 760, height: mode.height))
        Appearance.revealLauncher(height: mode.height, on: controller.view, duration: 0) {}
    }
    let views = qrCodeDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? QRCodeResultView }.first!
    let editor = NSTextView()
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally(); window.orderOut(nil) }
    var dismissals = 0
    controller.onDismiss = { dismissals += 1 }
    for command in ["qr", "QR Code Generator", "generator"] {
        controller.resetSearch()
        search.stringValue = command
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(!controller.isQRCodeMode && result.isHidden)
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        precondition(controller.isQRCodeMode && controller.displayMode == .qrCode && !result.isHidden)
        controller.view.layoutSubtreeIfNeeded()
        precondition(window.frame.size == NSSize(width: 760, height: 400))
        precondition(result.frame.size == NSSize(width: 760, height: 287))
        precondition(search.stringValue.isEmpty && result.code == nil)
        let copy = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Copy QR Code" }!
        precondition(!copy.isEnabled)
        search.stringValue = "  https://example.com/你好?q=one&two=2\nFlint 🌏  "
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(result.code != nil && copy.isEnabled && !controller.isTranslationMode)
        let png = result.code!.pngData
        controller.copyQRCode(to: pasteboard)
        precondition(pasteboard.data(forType: .png) == png && dismissals > 0)
        checkQRCodePreviews(controller.view, window: window)
        search.stringValue = String(repeating: "你", count: 667)
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(result.code == nil && !copy.isEnabled)
        let previousDismissals = dismissals
        controller.copyQRCode(to: pasteboard)
        precondition(dismissals == previousDismissals && pasteboard.data(forType: .png) == png)
        search.stringValue = "2+2"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(result.code != nil && controller.displayMode == .qrCode)
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        precondition(!controller.isQRCodeMode && result.isHidden && controller.displayMode == .collapsed)
        precondition(result.code == nil, "Leaving the tool must discard its payload and image")
    }
    search.stringValue = "qr"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(controller.isQRCodeMode)
    let composing = NSTextView()
    composing.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(!controller.control(search, textView: composing, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    precondition(controller.isQRCodeMode)
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
    precondition(!controller.isQRCodeMode)
    print("PASS: QR tool search, Tab/Return entry, exact PNG copying, capacity errors, calculation isolation, composition, Escape, and empty Backspace")
}

@MainActor
private func checkQRCodePreviews(_ view: NSView, window: NSWindow) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_QR_PREVIEW_DIR"] else { return }
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        window.appearance = NSAppearance(named: appearance)
        AppearanceCheckWindows.show(window)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = bitmap.representation(using: .png, properties: [:])!
        let scan = VNDetectBarcodesRequest()
        scan.symbologies = [.qr]
        try! VNImageRequestHandler(data: png).perform([scan])
        precondition(scan.results?.first?.payloadStringValue != nil, "The \(name) preview must remain scannable")
        try! png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("qr-code-\(name).png"))
        window.orderOut(nil)
    }
}

@MainActor
private func qrCodeDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(qrCodeDescendants)
}
