import AppKit

@MainActor
func checkCalculatorIntegration() {
    let controller = ApplicationsViewController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
    let views = calculatorDescendants(of: controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? CalculatorResultView }.first!
    let scroll = views.compactMap { $0 as? NSScrollView }.first!
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
    precondition(labels.count == 2 && labels.allSatisfy { $0.font?.pointSize == 36 })
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
    for query in ["3", "-3", "(3)", "1e3", "3+", "1/0", "3f", "1..2+3"] {
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
    precondition(mode == .calculator && labels.allSatisfy { $0.font?.pointSize == 36 })
    controller.resetSearch()
    precondition(mode == .collapsed && result.isHidden && !copy.isEnabled)
    precondition(calculatorIcon.alphaValue == 0 && searchIcon.alphaValue == 1)
    print("PASS: compact calculator, math typography, matching font sizes, icon changes, copying, errors, and search transitions")
}

@MainActor
private func calculatorDescendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + calculatorDescendants(of: $0) }
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
    let scroll = views.compactMap { $0 as? NSScrollView }.first!
    let results = scroll.superview!.superview!
    let top = window.frame.maxY
    let steps = [("1", 24), ("1+", 24), ("1+1", 24), ("", 24), ("a", 24), ("", 24),
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
