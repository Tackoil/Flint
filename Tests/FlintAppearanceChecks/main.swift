import AppKit

@main
struct AppearanceChecks {
    @MainActor static func main() {
        print(AppearanceCheckWindows.showsWindows ? "UI checks: visible windows" : "UI checks: offscreen windows; keyboard focus preserved")
        if ProcessInfo.processInfo.environment["FLINT_SCRIPT_ONLY"] == "1" {
            checkScriptCommands()
            return
        }
        if ProcessInfo.processInfo.environment["FLINT_CALCULATOR_ONLY"] == "1" {
            checkActionGroupResizing()
            checkCalculatorIntegration()
            return
        }
        if ProcessInfo.processInfo.environment["FLINT_NUMBER_BASE_ONLY"] == "1" {
            checkNumberBaseIntegration()
            return
        }
        if ProcessInfo.processInfo.environment["FLINT_TRANSLATION_ONLY"] == "1" {
            checkTranslationIntegration()
            return
        }
        if ProcessInfo.processInfo.environment["FLINT_MODE_SWITCHING_ONLY"] == "1" {
            checkKeyboardHintFeedback()
            checkColorConversionIntegration()
            checkNumericRoundingIntegration()
            checkRoundingModeSwitches()
            checkModeChangesOnKeyRelease()
            checkTimestampIntegration()
            checkTimestampKeyboardSwitching()
            return
        }
        if ProcessInfo.processInfo.environment["FLINT_QR_ONLY"] == "1" {
            checkQRCodeIntegration()
            return
        }
        if ProcessInfo.processInfo.environment["FLINT_QUICK_LINK_ONLY"] == "1" {
            checkQuickLinks()
            return
        }
        checkScriptCommands()
        checkQRCodeIntegration()
        checkQuickLinks()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
        let surface = Appearance.launcherSurface(content: content)
        Appearance.setLauncherCornerRadius(28, on: surface)
        let viewport = surface.subviews[0]
        let material = viewport.subviews[0]
        let header = LauncherHeaderFooter()
        let searchBar = header.searchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: content.topAnchor)
        ])
        surface.layoutSubtreeIfNeeded()
        let initialMaterialFrame = material.frame
        let initialSearchFrame = surface.convert(header.searchField.bounds, from: header.searchField)
        for height: CGFloat in [56, 56.5, 120.25, 200.5, 232, 559.75, 560, 320.25, 120, 56] {
            surface.setFrameSize(NSSize(width: 760, height: height))
            surface.needsLayout = true
            surface.layoutSubtreeIfNeeded()
            precondition(surface.isFlipped)
            precondition(material.frame == initialMaterialFrame)
            precondition(content.frame.height == 560)
            precondition(surface.convert(header.searchField.bounds, from: header.searchField) == initialSearchFrame)
        }
        surface.setFrameSize(NSSize(width: 760, height: 560))
        surface.layoutSubtreeIfNeeded()
        for height: CGFloat in [56, 120.25, 232, 560, 232, 320.25, 56] {
            Appearance.revealLauncher(height: height, on: surface, duration: 0) {}
            precondition(surface.frame.height == 560)
            precondition(viewport.frame.height == height)
            precondition(material.frame == initialMaterialFrame)
            precondition(surface.convert(header.searchField.bounds, from: header.searchField) == initialSearchFrame)
        }
        precondition(surface.appearance == nil)
        if #available(macOS 26.0, *) {
            let glass = material as! NSGlassEffectView
            precondition(glass.style == .regular)
            precondition(glass.tintColor == nil)
        }
        let chrome = AppearanceSurfaceView(fillColor: .quaternaryLabelColor, borderColor: .separatorColor)
        chrome.appearance = NSAppearance(named: .aqua)
        chrome.updateLayer()
        let light = NSColor(cgColor: chrome.layer!.backgroundColor!)!.usingColorSpace(.genericRGB)!
        chrome.appearance = NSAppearance(named: .darkAqua)
        chrome.updateLayer()
        let dark = NSColor(cgColor: chrome.layer!.backgroundColor!)!.usingColorSpace(.genericRGB)!
        precondition(light.redComponent < dark.redComponent)
        print("PASS: glass and search field stay stationary across collapsed, calculator, and expanded viewport heights")
        print("PASS: the reveal changes without resizing the window content or moving the search field")
        print("PASS: untinted native glass and inherited appearance")
        print("PASS: layer colors resolve for both light and dark appearances")
        checkLauncherDialog()
        checkKeyboardHintFeedback()
        checkActionGroupResizing()
        checkLauncherRowIcons()
        checkTranslationIntegration()
        checkColorConversionIntegration()
        checkCalculatorIntegration()
        checkNumberBaseIntegration()
        checkNumericRoundingIntegration()
        checkRoundingModeSwitches()
        checkModeChangesOnKeyRelease()
        checkTimestampIntegration()
        checkTimestampKeyboardSwitching()
        checkCalculatorToSearchTransitions()
    }
}
