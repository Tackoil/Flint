import AppKit
import CoreText

@MainActor
func checkTranslationIntegration() {
    checkSearchTruncation()
    checkSearchTabFocus()
    checkTranslationSkeletonStates()
    checkTranslationKeyboardNavigation()
    checkTranslationSourceTargets()
    checkTranslationMeanings()
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
    checkTranslationSettingsControls()
    checkTranslationSuccess()
    print("PASS: Translate uses action search, Tab enters, Return does not enter, input waits for a pause, and missing-key setup and Escape work")
}

@MainActor
private func checkTranslationMeanings() {
    let suite = "FlintTranslationMeaningChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TranslationPreferences(defaults: defaults)
    preferences.targetLanguages = [.simplifiedChinese]
    let client = DeepSeekTranslationClient { request in
        var payload: [String: Any] = ["translation": "银行", "source_language": "en",
            "explanation": "指办理存款、贷款等金融业务的机构。例如：去银行开户。",
            "alternate_meanings": ["河岸：河流两侧的陆地。例如：坐在河岸边。",
                                   "储备库：集中储存某种资源的地方，例如血库或数据库。",
                                   "倾斜转弯：飞机或车辆在转弯时向一侧倾斜。"]]
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let input = (body["messages"] as! [[String: String]]).last!["content"]
        if input == "bank (long definitions)" {
            payload["explanation"] = String(repeating: "指办理存款、贷款等金融业务的机构。例如：去银行开户。\n", count: 20)
        }
        let content = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content], "finish_reason": "stop"]]
        ])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let session = TranslationSession(client: client, readAPIKey: { "test-key" })
    let controller = ApplicationsViewController(translationSession: session, translationPreferences: preferences)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = translationDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
    search.stringValue = "bank"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    waitForTranslation(session, answer: "银行")
    let result = views.compactMap { $0 as? TranslationResultView }.first!
    let output = translationDescendants(result).compactMap { $0 as? NSTextView }.first!
    precondition(output.string.hasPrefix("银行\n\nMeaning\n"))
    precondition(output.string.contains("\n\nOther meanings\n1. 河岸"))
    precondition(output.string.contains("\n\n2. 储备库") && output.string.contains("\n\n3. 倾斜转弯"))
    let font = output.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
    let detailFont = output.textStorage!.attribute(.font, at: output.string.count - 1, effectiveRange: nil) as! NSFont
    precondition(font.pointSize > detailFont.pointSize, "The primary translation must remain visually prominent")
    for (name, appearance) in [("meanings-light", NSAppearance.Name.aqua), ("meanings-dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        renderTranslationPreview(controller.view, name: name)
    }
    preferences.targetLanguages = [.simplifiedChinese, .japanese]
    result.configure(session, preferences: preferences)
    renderTranslationPreview(controller.view, name: "meanings-with-preview")
    search.stringValue = "bank (long definitions)"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    waitForTranslation(session, answer: "银行")
    renderTranslationPreview(controller.view, name: "meanings-scrolling")
    precondition(output.frame.height > output.enclosingScrollView!.bounds.height, "Long meaning lists must scroll")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    controller.copyTranslationAnswer(to: pasteboard)
    precondition(pasteboard.string(forType: .string) == "银行", "Copy Translation must copy only the primary translation")
    search.stringValue = "river bank"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(output.string.isEmpty, "Editing must clear every section of the previous result")
    controller.resetSearch()
    print("PASS: word descriptions and numbered alternate meanings render below the translation, scroll, copy cleanly, and clear on edit")
}

private struct TranslationSourceCheckClient: TranslationServing {
    func translate(_ text: String, to language: TranslationLanguage, apiKey: String) async throws -> TranslationResponse {
        let translations: [TranslationLanguage: String] = [.english: "anxious", .simplifiedChinese: "焦虑的", .japanese: "不安な"]
        return TranslationResponse(text: translations[language]!, sourceLanguage: .init(code: "en", origin: .deepSeek))
    }
}

@MainActor
private func checkTranslationSourceTargets() {
    let suite = "FlintTranslationSourceChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TranslationPreferences(defaults: defaults)
    let saved: [TranslationLanguage] = [.english, .simplifiedChinese, .japanese]
    preferences.targetLanguages = saved
    preferences.targetLanguage = .english
    let session = TranslationSession(client: TranslationSourceCheckClient(),
                                     inferSourceLanguage: { _ in .init(code: "en") }, readAPIKey: { "test-key" })
    let controller = ApplicationsViewController(translationSession: session, translationPreferences: preferences)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = translationDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let result = views.compactMap { $0 as? TranslationResultView }.first!
    let candidate = translationDescendants(result).compactMap { $0 as? TranslationCandidatePreviewView }.first!
    let editor = NSTextView()
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    search.stringValue = "anxious"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    waitForTranslation(session, answer: "焦虑的")
    precondition(session.language == .simplifiedChinese && preferences.targetLanguage == .simplifiedChinese)
    precondition(candidate.language == .japanese && preferences.targetLanguages == saved)
    for (name, appearance) in [("skip-source-light", NSAppearance.Name.aqua), ("skip-source-dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        renderTranslationPreview(controller.view, name: name)
    }
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:)))
    waitForTranslation(session, answer: "不安な")
    precondition(candidate.language == .simplifiedChinese)
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:)))
    precondition(session.state.answer == "焦虑的", "Cycling must wrap directly past the source language to the cached target")
    preferences.targetLanguages = [.english, .japanese]
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(session.language == .japanese && candidate.isHidden, "A single remaining target must hide the next preview")
    preferences.targetLanguages = [.english]
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    waitForTranslation(session, answer: "焦虑的")
    precondition(candidate.isHidden && preferences.targetLanguages == [.english])
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:)))
    precondition(preferences.targetLanguages == [.english], "A temporary fallback must not be added to saved targets")
    renderTranslationPreview(controller.view, name: "skip-source-only-saved-target")
    search.stringValue = ""
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(session.sourceLanguage == nil && session.language == .english)
    controller.resetSearch()
    print("PASS: source targets are skipped before translation, in cycling and previews; single-target fallback preserves Settings")
}

private struct TranslationLanguageCheckClient: TranslationServing {
    func translate(_ text: String, to language: TranslationLanguage, apiKey: String) async throws -> TranslationResponse {
        TranslationResponse(text: "\(language.rawValue): \(text)", sourceLanguage: .init(code: "fr"))
    }
}

private struct TranslationLoadingCheckClient: TranslationServing {
    func translate(_ text: String, to language: TranslationLanguage, apiKey: String) async throws -> TranslationResponse {
        try await Task.sleep(for: .seconds(60))
        return TranslationResponse(text: "Unused", sourceLanguage: nil)
    }
}

@MainActor
private func checkTranslationSkeletonStates() {
    let suite = "FlintTranslationSkeletonChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TranslationPreferences(defaults: defaults)
    preferences.targetLanguages = [.english, .japanese]
    let result = TranslationResultView()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 400),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = result
    let session = TranslationSession(client: TranslationLoadingCheckClient(),
                                     waitForTypingPause: { try await Task.sleep(for: .seconds(60)) },
                                     readAPIKey: { "test-key" })
    defer { session.cancel() }
    session.update(query: nil, language: .english)
    result.configure(session, preferences: preferences)
    let skeleton = translationDescendants(result).compactMap { $0 as? TranslationSkeletonView }.first!
    let candidate = translationDescendants(result).compactMap { $0 as? TranslationCandidatePreviewView }.first!
    precondition(!skeleton.isHidden && candidate.language == .japanese && !candidate.isHidden)
    result.appearance = NSAppearance(named: .aqua)
    renderTranslationPreview(result, name: "skeleton-ready-light")
    result.layoutSubtreeIfNeeded()
    let nextFrame = result.convert(candidate.bounds, from: candidate)
    let primaryFrame = result.convert(skeleton.bounds, from: skeleton)
    precondition(candidate.alphaValue == 0.4 && nextFrame.minX > primaryFrame.maxX)
    precondition(nextFrame.maxX == result.bounds.maxX)
    let fade = candidate.layer!.mask as! CAGradientLayer
    precondition(fade.frame == candidate.bounds && fade.startPoint.x == 0 && fade.endPoint.x == 1)
    session.update(query: .init(text: "Hello"), language: .english)
    result.configure(session, preferences: preferences)
    precondition(!skeleton.isHidden && session.state == .waiting)
    precondition(skeleton.layer?.animation(forKey: "translationSkeletonPulse") == nil,
                 "The typing pause must keep skeletons static until the API request starts")
    session.submit()
    result.configure(session, preferences: preferences)
    precondition(!skeleton.isHidden && session.state == .loading)
    precondition(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                 || skeleton.layer?.animation(forKey: "translationSkeletonPulse") != nil)
    if let pulse = skeleton.layer?.animation(forKey: "translationSkeletonPulse") as? CABasicAnimation {
        precondition(pulse.autoreverses && pulse.repeatCount == .infinity && pulse.duration < 0.7)
    }
    result.appearance = NSAppearance(named: .darkAqua)
    renderTranslationPreview(result, name: "skeleton-loading-dark")
    checkTranslationErrorStates(result, skeleton: skeleton, preferences: preferences)
    preferences.targetLanguages = [.english]
    result.configure(session, preferences: preferences)
    result.layoutSubtreeIfNeeded()
    precondition(candidate.isHidden && candidate.language == nil)
    precondition(skeleton.frame.width > 680, "A single target must use the full result width")
    print("PASS: empty/waiting/loading skeletons, dimmed next-language preview, readable errors, and single-target layout")
}

@MainActor
private func checkTranslationErrorStates(_ result: TranslationResultView, skeleton: TranslationSkeletonView,
                                         preferences: TranslationPreferences) {
    for readKey: () throws -> String? in [{ nil }, { throw TranslationError.network }] {
        let session = TranslationSession(readAPIKey: readKey)
        session.update(query: .init(text: "Hello"), language: .english)
        session.submit()
        result.configure(session, preferences: preferences)
        precondition(skeleton.isHidden && skeleton.layer?.animation(forKey: "translationSkeletonPulse") == nil)
        let messages = translationDescendants(result).compactMap { $0 as? NSTextField }
            .filter { !$0.isHiddenOrHasHiddenAncestor && !$0.stringValue.isEmpty }
        precondition(messages.contains { $0.stringValue.contains("API key") || $0.stringValue.contains("connect") })
    }
}

@MainActor
private func checkTranslationKeyboardNavigation() {
    let suite = "FlintTranslationKeyboardChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TranslationPreferences(defaults: defaults)
    preferences.targetLanguages = [.english, .simplifiedChinese, .traditionalChinese]
    preferences.targetLanguage = .english
    let session = TranslationSession(client: TranslationLanguageCheckClient(),
                                     inferSourceLanguage: { _ in .init(code: "fr") }, readAPIKey: { "test-key" })
    let controller = ApplicationsViewController(translationSession: session, translationPreferences: preferences)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    let views = translationDescendants(controller.view)
    let search = views.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let button = views.compactMap { $0 as? NSButton }
        .first { $0.action == NSSelectorFromString("toggleTranslationLanguageSwitchingMode") }!
    let editor = NSTextView()
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    let result = views.compactMap { $0 as? TranslationResultView }.first!
    let skeleton = translationDescendants(result).compactMap { $0 as? TranslationSkeletonView }.first!
    let candidate = translationDescendants(result).compactMap { $0 as? TranslationCandidatePreviewView }.first!
    precondition(!skeleton.isHidden && candidate.language == .simplifiedChinese)
    renderTranslationPreview(controller.view, name: "empty-with-next-language")
    search.stringValue = "Hello"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    waitForTranslation(session, answer: "English: Hello")
    precondition(skeleton.isHidden && candidate.language == .simplifiedChinese)
    precondition(button.accessibilityLabel() == "Edit text")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    precondition(preferences.targetLanguage == .traditionalChinese && session.language == .traditionalChinese)
    precondition(session.state == .waiting && session.state.answer == nil && search.stringValue == "Hello")
    precondition(!skeleton.isHidden && candidate.language == .english)
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(preferences.targetLanguage == .english, "Right must wrap back to the first saved language")
    checkTranslationArrowRelease(controller, search: search, preferences: preferences, window: window)
    checkTranslationEditing(controller, search: search, button: button, preferences: preferences)
    precondition(preferences.targetLanguage == .traditionalChinese)
    waitForTranslation(session, answer: "Traditional Chinese: Edited text")
    precondition(skeleton.isHidden && candidate.language == .english)
    checkCachedTranslationSwitch(controller, search: search, session: session, result: result, window: window)
    precondition(candidate.response?.text == "English: Edited text")
    for (name, appearance) in [("switching-light", NSAppearance.Name.aqua), ("switching-dark", .darkAqua)] {
        controller.view.appearance = NSAppearance(named: appearance)
        renderTranslationPreview(controller.view, name: name)
    }
    checkTranslationFooterBounds(controller.view)
    button.performClick(nil)
    renderTranslationPreview(controller.view, name: "editing")
    checkTranslationFooterBounds(controller.view)
    controller.resetSearch()
    search.stringValue = "translate"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    precondition(button.accessibilityLabel() == "Edit text", "Reentering Translate must restore language switching")
    precondition(session.language == .traditionalChinese)
    preferences.targetLanguages = [.traditionalChinese]
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(session.language == .traditionalChinese)
    controller.resetSearch()
    precondition(button.isHidden)
    print("PASS: translation arrows wrap saved targets, retranslate unchanged input, preserve editing, and reset on reentry")
}

@MainActor
private func checkCachedTranslationSwitch(_ controller: ApplicationsViewController, search: NSTextField,
                                          session: TranslationSession, result: TranslationResultView, window: NSWindow) {
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    window.contentView?.layoutSubtreeIfNeeded()
    let output = translationDescendants(result).compactMap { $0 as? NSTextView }.first!
    let primary = output.enclosingScrollView!.superview!
    let editor = NSTextView()
    let right = #selector(NSResponder.moveRight(_:))
    let left = #selector(NSResponder.moveLeft(_:))
    precondition(controller.control(search, textView: editor, doCommandBy: right))
    precondition(session.language == .english, "The right-arrow action must switch the target before checking its animation")
    checkTranslationSwitchAnimation(primary, subtype: .fromRight)
    waitForTranslation(session, answer: "English: Edited text")
    precondition(controller.control(search, textView: editor, doCommandBy: left))
    precondition(session.state.answer == "Traditional Chinese: Edited text", "Cached targets must restore immediately")
    checkTranslationSwitchAnimation(primary, subtype: .fromLeft)
    precondition(controller.control(search, textView: editor, doCommandBy: right))
    precondition(session.state.answer == "English: Edited text")
    checkTranslationSwitchAnimation(primary, subtype: .fromRight)
    precondition(controller.control(search, textView: editor, doCommandBy: left))
    precondition(session.state.answer == "Traditional Chinese: Edited text")
    checkTranslationSwitchAnimation(primary, subtype: .fromLeft)
    CATransaction.flush()
    let timeout = Date().addingTimeInterval(2)
    while primary.layer?.animation(forKey: "transition") != nil && Date() < timeout {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(primary.layer?.animation(forKey: "transition") == nil, "Completed transitions must be removed")
    print("PASS: cached targets restore immediately, preview cached answers, and slide/fade in both directions")
}

@MainActor
private func checkTranslationSwitchAnimation(_ primary: NSView, subtype: CATransitionSubtype) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(primary.layer?.animation(forKey: "transition") == nil)
        return
    }
    guard let transition = primary.layer?.animation(forKey: "transition") as? CATransition else {
        preconditionFailure("Missing slide on \(type(of: primary)); visible: \(primary.window?.isVisible == true); keys: \(primary.layer?.animationKeys() ?? [])")
    }
    precondition(transition.type == .push && transition.subtype == subtype)
    precondition(primary.layer?.animation(forKey: "translationSwitchOpacity") != nil)
}

@MainActor
private func checkTranslationEditing(_ controller: ApplicationsViewController, search: NSTextField,
                                     button: NSButton, preferences: TranslationPreferences) {
    let editor = NSTextView()
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
    precondition(button.accessibilityLabel() == "Switch language")
    for selector in [#selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
                     #selector(NSResponder.moveWordRight(_:)), #selector(NSResponder.moveLeftAndModifySelection(_:))] {
        precondition(!controller.control(search, textView: editor, doCommandBy: selector))
    }
    search.stringValue = "Edited text"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    precondition(button.accessibilityLabel() == "Switch language", "Typing must retain editing mode")
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    precondition(button.accessibilityLabel() == "Edit text")
    let before = preferences.targetLanguage
    editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(!controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(preferences.targetLanguage == before, "Composing text must retain its input-method arrow behavior")
    editor.unmarkText()
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Switch language")
    button.performClick(nil)
    precondition(button.accessibilityLabel() == "Edit text")
}

@MainActor
private func checkTranslationArrowRelease(_ controller: ApplicationsViewController, search: NSTextField,
                                         preferences: TranslationPreferences, window: NSWindow) {
    let hints = translationDescendants(controller.view).compactMap { $0 as? KeyboardHintView }
    let right = hints.first { $0.hint == .rightArrow && !$0.isHiddenOrHasHiddenAncestor }!
    let editor = NSTextView()
    right.handleKeyEvent(translationArrowEvent(124))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    precondition(preferences.targetLanguage == .english && right.isKeyPressed)
    right.handleKeyEvent(translationArrowEvent(124, isRepeat: true))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    right.handleKeyEvent(translationArrowEvent(124, type: .keyUp))
    precondition(preferences.targetLanguage == .simplifiedChinese && !right.isKeyPressed)
    right.handleKeyEvent(translationArrowEvent(124, type: .keyUp))
    precondition(preferences.targetLanguage == .simplifiedChinese, "Release must switch exactly once")
    right.handleKeyEvent(translationArrowEvent(124))
    precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    right.handleKeyEvent(translationArrowEvent(124, type: .keyUp))
    precondition(preferences.targetLanguage == .simplifiedChinese, "Losing focus must cancel the pending switch")
}

private func translationArrowEvent(_ keyCode: UInt16, type: NSEvent.EventType = .keyDown,
                                   isRepeat: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                    context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: isRepeat, keyCode: keyCode)!
}

@MainActor
private func waitForTranslation(_ session: TranslationSession, answer: String) {
    let timeout = Date().addingTimeInterval(3)
    while session.state.answer != answer && Date() < timeout {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(session.state.answer == answer, "Translation must run with the new target")
}

@MainActor
private func checkTranslationFooterBounds(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    let group = translationDescendants(view).compactMap { $0 as? ActionGroupView }.first!
    let surface = group.convert(group.surface.bounds, from: group.surface)
    let hints = translationDescendants(group).compactMap { $0 as? KeyboardHintView }
    for hint in hints where !hint.isHiddenOrHasHiddenAncestor {
        precondition(surface.contains(group.convert(hint.bounds, from: hint)),
                     "All translation footer controls must fit inside the action group")
    }
}

@MainActor
private func checkSearchTruncation() {
    let header = LauncherHeaderFooter()
    let bar = header.searchBar()
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 56),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = bar
    AppearanceCheckWindows.show(window)
    defer { window.orderOut(nil) }
    bar.layoutSubtreeIfNeeded()
    window.makeFirstResponder(header.searchField)
    let editor = header.searchField.currentEditor() as! NSTextView
    let source = String(repeating: "Long translation input with all of its words preserved. ", count: 12)
    editor.insertText(source, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    let container = editor.textContainer!
    let manager = editor.layoutManager!
    manager.ensureLayout(for: container)
    precondition(header.searchField.stringValue == source && editor.string == source)
    precondition(header.searchField.lineBreakMode == .byTruncatingTail)
    precondition(container.maximumNumberOfLines == 1 && container.lineBreakMode == .byTruncatingTail)
    renderTranslationPreview(bar, name: "search-truncated")
    precondition(manager.truncatedGlyphRange(inLineFragmentForGlyphAt: 0).location != NSNotFound,
                 "Long focused search input must end with an ellipsis: container \(container.containerSize), editor \(editor.frame)")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let examples = [("search-paragraphs", "First paragraph.\n\n" + source),
                    ("search-crlf", "First paragraph.\r\nSecond paragraph.\r\n" + source),
                    ("search-line-separators", "First paragraph.\u{2028}Second paragraph.\u{2029}" + source)]
    for (name, multiline) in examples {
        pasteboard.setString(multiline, forType: .string)
        editor.selectAll(nil)
        precondition(editor.readSelection(from: pasteboard, type: .string))
        manager.ensureLayout(for: container)
        precondition(header.searchField.stringValue == multiline, "Single-line presentation must preserve pasted paragraphs")
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, _, _ in lines += 1 }
        precondition(lines == 1, "Pasted paragraphs must not wrap below the search bar")
        let lineBreak = (multiline as NSString).rangeOfCharacter(from: .newlines).location
        let glyph = manager.glyphIndexForCharacter(at: lineBreak)
        precondition(manager.cgGlyph(at: glyph) != 0 && !manager.propertyForGlyph(at: glyph).contains(.controlCharacter),
                     "Line breaks must draw a visible return symbol")
        checkReturnSymbolSpacing(manager, source: multiline as NSString, lineBreak: lineBreak, font: header.searchField.font!)
        precondition(manager.truncatedGlyphRange(inLineFragmentForGlyphAt: 0).location != NSNotFound,
                     "Hidden pasted paragraphs must also be indicated by an ellipsis")
        renderTranslationPreview(bar, name: name)
    }
    print("PASS: focused search truncates to one line, draws return symbols, and preserves original LF, CRLF, and Unicode line breaks")
}

@MainActor
private func checkReturnSymbolSpacing(_ manager: NSLayoutManager, source: NSString, lineBreak: Int, font: NSFont) {
    let isCRLF = source.character(at: lineBreak) == 13 && source.character(at: lineBreak + 1) == 10
    let symbolIndex = manager.glyphIndexForCharacter(at: lineBreak)
    let nextIndex = manager.glyphIndexForCharacter(at: lineBreak + (isCRLF ? 2 : 1))
    var symbol = manager.cgGlyph(at: symbolIndex)
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &symbol, &advance, 1)
    let spacing = manager.location(forGlyphAt: nextIndex).x - manager.location(forGlyphAt: symbolIndex).x
    precondition(abs(spacing - advance.width) < 1,
                 "Return symbols must use their natural width, without extra spacing or overlap: \(spacing) vs \(advance.width)")
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
    for query in ["Finder", "3+", "#zzzz"] {
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
    for child in settings.arrangedSubviews where !child.isHidden {
        precondition(child.frame.width > 0 && child.frame.height > 0)
        precondition(settings.bounds.insetBy(dx: -1, dy: -1).contains(child.alignmentRect(forFrame: child.frame)),
                     "Translation settings must fit without clipping: \(type(of: child)) \(child.frame) in \(settings.bounds)")
    }
}

@MainActor
private func checkTranslationSettingsControls() {
    let suite = "FlintTranslationSettingsChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = TranslationPreferences(defaults: defaults)
    preferences.targetLanguage = .thai
    var storedKey: String?
    let settings = TranslationSettingsView(preferences: preferences, hasAPIKey: { storedKey?.isEmpty == false },
                                           saveAPIKey: { storedKey = $0 }, deleteAPIKey: { storedKey = nil })
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 492, height: 400),
                                       styleMask: [.titled], backing: .buffered, defer: false)
    let content = NSView(frame: window.contentLayoutRect)
    window.contentView = content
    settings.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(settings)
    NSLayoutConstraint.activate([
        settings.leadingAnchor.constraint(equalTo: content.leadingAnchor),
        settings.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        settings.topAnchor.constraint(equalTo: content.topAnchor)
    ])
    content.layoutSubtreeIfNeeded()
    let views = translationDescendants(settings)
    let table = views.compactMap { $0 as? NSTableView }.first!
    precondition(table.numberOfRows == 1 && preferences.targetLanguages == [.thai])
    precondition(preferences.targetLanguages[table.selectedRow] == preferences.targetLanguage)
    precondition(table.visibleRect.intersects(table.rect(ofRow: table.selectedRow)),
                 "The saved target language must be visible when settings opens")
    let addLanguage = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Add language" }!
    let removeLanguage = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Remove language" }!
    precondition(!removeLanguage.isEnabled, "Keep at least one translation target")
    for language in TranslationLanguage.allCases where language != .thai {
        let menu = addLanguage.menu!
        let index = menu.items.firstIndex { $0.representedObject as? String == language.rawValue }!
        menu.performActionForItem(at: index)
        precondition(preferences.targetLanguage == language && preferences.targetLanguages.last == language)
    }
    precondition(table.numberOfRows == TranslationLanguage.allCases.count && !addLanguage.isEnabled)
    let last = preferences.targetLanguages.count - 1
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    precondition(preferences.targetLanguage == .thai)
    table.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
    precondition(preferences.targetLanguage == preferences.targetLanguages[last])
    table.scrollRowToVisible(last)
    precondition(table.visibleRect.intersects(table.rect(ofRow: last)), "Every language must be reachable by scrolling")
    while preferences.targetLanguages.count > 1 {
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        removeLanguage.performClick(nil)
    }
    precondition(preferences.targetLanguages == [.thai] && !removeLanguage.isEnabled)
    precondition(addLanguage.isEnabled && table.numberOfRows == 1)
    let field = views.compactMap { $0 as? NSSecureTextField }.first!
    let buttons = views.compactMap { $0 as? NSButton }
    let save = buttons.first { $0.title == "Save Key" }!
    let remove = buttons.first { $0.accessibilityLabel() == "Remove API key" }!
    precondition(!field.isHidden && !save.isHidden && remove.isHidden)
    field.stringValue = "test-key-never-written-to-keychain"
    save.performClick(nil)
    precondition(storedKey == "test-key-never-written-to-keychain")
    precondition(field.stringValue.isEmpty && field.isHidden && save.isHidden && !remove.isHidden)
    precondition(remove.title.isEmpty && remove.image != nil, "Saved keys must use an icon-only remove control")
    precondition(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "••••••••••••" && !$0.isHidden })
    content.layoutSubtreeIfNeeded()
    let keyTitle = views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "DeepSeek API Key" }!
    let dots = views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "••••••••••••" }!
    let titleFrame = content.convert(keyTitle.bounds, from: keyTitle)
    let valueFrame = content.convert(dots.bounds, from: dots)
    precondition(abs(titleFrame.midY - valueFrame.midY) < 2 && valueFrame.minX > titleFrame.maxX,
                 "The API key label and masked value must share a row, with the value on the right")
    for (name, appearance) in [("saved-light", NSAppearance.Name.aqua), ("saved-dark", .darkAqua)] {
        settings.appearance = NSAppearance(named: appearance)
        renderTranslationPreview(content, name: "settings-\(name)")
    }
    remove.performClick(nil)
    precondition(storedKey == nil && !field.isHidden && !save.isHidden && remove.isHidden)
    precondition(buttons.allSatisfy { !$0.title.contains("Get a DeepSeek") && $0.title != "Remove Key" })
    print("PASS: languages can be added and removed, selection persists, and the API key uses a single masked form row")
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
        let payload = try JSONSerialization.data(withJSONObject: ["translation": expected, "source_language": "en"])
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": String(data: payload, encoding: .utf8)!], "finish_reason": "stop"]]
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
    precondition(session.sourceLanguage?.code == "en")
    precondition(session.sourceLanguage?.origin == .deepSeek)
    let heading = translationDescendants(controller.view).compactMap { $0 as? NSTextField }
        .first { $0.stringValue == "English → \(session.language.rawValue) · DeepSeek" }
    precondition(heading != nil && !heading!.isHiddenOrHasHiddenAncestor,
                 "Translation must show the inferred source language")
    precondition(heading!.toolTip == "Source language inferred by DeepSeek.")
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
    precondition(session.sourceLanguage == nil)
    precondition(heading!.stringValue == "Auto-detect → \(session.language.rawValue) · DeepSeek")
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
