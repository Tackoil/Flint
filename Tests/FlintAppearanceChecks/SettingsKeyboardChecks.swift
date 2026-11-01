import AppKit

@MainActor
func checkSettingsKeyboard() {
    let suite = "FlintSettingsKeyboard-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    let preferences = LauncherPreferences(defaults: defaults)
    let links = QuickLinkStore(defaults: defaults)
    try! links.save(QuickLink(name: "First", link: "https://example.com/first"))
    try! links.save(QuickLink(name: "Second", link: "https://example.com/second"))
    let scripts = ScriptCommandStore(defaults: defaults)
    try! ScriptCommandStore.template.write(to: directory.appendingPathComponent("hello.sh"), atomically: true, encoding: .utf8)
    scripts.add(directory)
    let translation = TranslationPreferences(defaults: defaults)
    translation.targetLanguages = [.english, .french]
    translation.targetLanguage = .english
    var key: String?
    let translationView = TranslationSettingsView(preferences: translation, hasAPIKey: { key != nil },
                                                  saveAPIKey: { key = $0 }, deleteAPIKey: { key = nil })
    let controller = SettingsViewController(preferences: preferences, onShortcutChange: { _ in true },
                                            onRecordingStateChange: { _ in }, onMenuBarVisibilityChange: { _ in },
                                            scriptStore: scripts, quickLinkStore: links, translationSettings: translationView)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    AppearanceCheckWindows.show(window)
    let keyboard = controller.view as! SettingsKeyboardView
    checkArrowSelection(keyboard, preferences: preferences)
    checkGeneralKeyboard(keyboard, preferences: preferences)
    checkSettingsActionsPopover(keyboard, window: window)
    checkTranslationKeyboard(keyboard, settings: translationView, preferences: translation, savedKey: { key })
    checkQuickLinkKeyboard(keyboard, window: window, store: links)
    checkScriptKeyboard(keyboard, store: scripts)
    checkSettingsKeyboardPreviews(keyboard, window: window)
    precondition(!window.isKeyWindow, "Settings checks must preserve the user's keyboard focus")
    pressSettingsKey(keyboard, 53, "\u{1b}")
    precondition(window.isVisible && keyboard.isInSidebar, "Escape must return from content to the sidebar")
    pressSettingsKey(keyboard, 53, "\u{1b}")
    precondition(!window.isVisible, "Escape must close Settings")
    print("PASS: Settings keyboard-only toggles, focus traversal, section shortcuts, language selection, API-key editing, quick-link save/cancel/removal, script refresh/removal, and offscreen action-group layouts")
}

@MainActor
private func checkArrowSelection(_ keyboard: SettingsKeyboardView, preferences: LauncherPreferences) {
    keyboard.focusFirstControl()
    pressSettingsKey(keyboard, 126, "\u{f700}")
    precondition(keyboard.focusedControl?.accessibilityLabel() == "Open at Login", "Up must clamp at the first setting")
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(keyboard.focusedControl?.accessibilityLabel() == "Show in Menu Bar")
    let before = preferences.showInMenuBar
    pressSettingsKey(keyboard, 36, "\r")
    precondition(preferences.showInMenuBar != before)
    pressSettingsKey(keyboard, 124, "\u{f703}")
    precondition(preferences.showInMenuBar != before, "Right must not change a switch while browsing rows")
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(keyboard.focusedControl?.accessibilityLabel() == "Switch to ABC")
    let remembered = keyboard.focusedControl
    pressSettingsKey(keyboard, 123, "\u{f702}")
    precondition(keyboard.isInSidebar)
    pressSettingsKey(keyboard, 123, "\u{f702}")
    precondition(keyboard.isInSidebar && keyboard.window?.isVisible == true,
                 "Left must stop at the sidebar rather than close Settings")
    precondition(keyboard.handleKeyDown(settingsKey(53, "\u{1b}", isRepeat: true)))
    precondition(keyboard.window?.isVisible == true, "Repeating Escape must not dismiss another navigation level")
    pressSettingsKey(keyboard, 124, "\u{f703}")
    precondition(keyboard.focusedControl === remembered, "Right must restore the selected settings row")
    pressSettingsKey(keyboard, 53, "\u{1b}")
    pressSettingsKey(keyboard, 126, "\u{f700}")
    precondition(keyboard.isInSidebar && keyboard.focusedControl?.accessibilityLabel() == "General")
    pressSettingsKey(keyboard, 36, "\r")
    precondition(!keyboard.isInSidebar)
}

@MainActor
private func checkGeneralKeyboard(_ keyboard: SettingsKeyboardView, preferences: LauncherPreferences) {
    let input = settingsViews(keyboard).compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "Switch to ABC" }!
    keyboard.focus(input)
    precondition(keyboard.focusedControl === input)
    let before = preferences.switchToABC
    pressSettingsKey(keyboard, 49, " ")
    precondition(preferences.switchToABC != before, "Space must toggle the focused switch")
    pressSettingsKey(keyboard, 48, "\t", modifiers: .shift)
    precondition((keyboard.focusedControl as? NSControl)?.accessibilityLabel() == "Show in Menu Bar")
    pressSettingsKey(keyboard, 48, "\t")
    precondition(keyboard.focusedControl === input)
    pressSettingsKey(keyboard, 48, "\t")
    let recorder = keyboard.focusedControl as! ShortcutRecorder
    pressSettingsKey(keyboard, 36, "\r")
    precondition(recorder.isRecording)
    precondition(!keyboard.handleKeyDown(settingsKey(21, "4", modifiers: .command)),
                 "Settings shortcuts must yield while recording a launcher shortcut")
    pressSettingsKey(keyboard, 48, "\t")
    precondition(!recorder.isRecording && keyboard.focusedControl !== recorder,
                 "Tab must stop shortcut recording and advance through the explicit focus order")
    pressSettingsKey(keyboard, 126, "\u{f700}")
    precondition(keyboard.focusedControl === recorder, "Arrow navigation must return from an icon action to its setting row")
    keyboard.focus(keyboard.controls().last!)
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition((keyboard.focusedControl as? NSButton)?.accessibilityLabel() == "Quick Links")
    pressSettingsKey(keyboard, 18, "1", modifiers: .command)
    precondition(!keyboard.visibleActions.contains { ["General", "Quick Links", "Scripts", "Translation"].contains($0.title) },
                 "The Actions menu must contain section actions without duplicating sidebar navigation")
    let menu = NSMenu(title: "Language menu")
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
    precondition(!keyboard.handleKeyDown(settingsKey(125, "\u{f701}")))
    precondition(!keyboard.handleKeyDown(settingsKey(53, "\u{1b}")),
                 "Native menus must receive arrows and Escape while tracking")
    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
}

@MainActor
private func checkTranslationKeyboard(_ keyboard: SettingsKeyboardView, settings: TranslationSettingsView,
                                      preferences: TranslationPreferences, savedKey: () -> String?) {
    pressSettingsKey(keyboard, 21, "4", modifiers: .command)
    let languages = keyboard.focusedControl as! NSTableView
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(preferences.targetLanguage == .french)
    pressSettingsKey(keyboard, 48, "\t")
    precondition((keyboard.focusedControl as? NSControl)?.accessibilityLabel() == "Add language")
    pressSettingsKey(keyboard, 48, "\t")
    precondition((keyboard.focusedControl as? NSControl)?.accessibilityLabel() == "Remove language")
    pressSettingsKey(keyboard, 48, "\t")
    let field = keyboard.focusedControl as! NSSecureTextField
    let targets = preferences.targetLanguages
    precondition(!keyboard.handleKeyDown(settingsKey(51, "\u{7f}", modifiers: .command)),
                 "Command–Delete must edit text rather than remove a language while a field is being edited")
    precondition(preferences.targetLanguages == targets)
    field.stringValue = "fixture-key-stored-only-in-memory"
    pressSettingsKey(keyboard, 36, "\r")
    precondition(savedKey() == "fixture-key-stored-only-in-memory")
    precondition(keyboard.focusedControl === languages && field.isHidden,
                 "Focus must leave a field when saving hides it")
    pressSettingsKey(keyboard, 51, "\u{7f}", modifiers: [.command, .shift])
    precondition(savedKey() == nil && !field.isHidden)
    pressSettingsKey(keyboard, 51, "\u{7f}", modifiers: .command)
    precondition(preferences.targetLanguages == [.english])
    let remove = settings.keyboardControls.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Remove language" }!
    precondition(!remove.isEnabled)
    keyboard.focus(languages)
    pressSettingsKey(keyboard, 48, "\t")
    pressSettingsKey(keyboard, 48, "\t")
    precondition(keyboard.focusedControl === field, "Tab must skip the disabled remove-language control")
    precondition(!keyboard.handleKeyDown(settingsKey(49, " ")), "Text editing must retain the Space key")
}

@MainActor
private func checkQuickLinkKeyboard(_ keyboard: SettingsKeyboardView, window: NSWindow, store: QuickLinkStore) {
    pressSettingsKey(keyboard, 19, "2", modifiers: .command)
    let table = keyboard.focusedControl as! NSTableView
    precondition(table.selectedRow == 0)
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(table.selectedRow == 1)
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(table.selectedRow == 1 && keyboard.focusedControl === table, "Arrow navigation must stay in the link list")
    pressSettingsKey(keyboard, 36, "\r")
    let sheet = window.attachedSheet!
    let editor = sheet.contentView as! SettingsKeyboardView
    precondition(!sheet.isKeyWindow && !window.isKeyWindow)
    let name = settingsViews(editor).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link name" }!
    let destination = settingsViews(editor).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Quick link destination" }!
    editor.focusFirstControl()
    precondition(editor.focusedControl === name && !editor.isEditingText)
    pressSettingsKey(editor, 125, "\u{f701}")
    precondition(editor.focusedControl === destination && !editor.isEditingText)
    pressSettingsKey(editor, 36, "\r")
    precondition(editor.isEditingText)
    precondition(!editor.handleKeyDown(settingsKey(123, "\u{f702}")), "Editing must keep native cursor arrows")
    precondition(!editor.handleKeyDown(settingsKey(125, "\u{f701}")))
    pressSettingsKey(editor, 53, "\u{1b}")
    precondition(!editor.isEditingText && window.attachedSheet === sheet, "Escape must finish editing before cancelling")
    pressSettingsKey(editor, 126, "\u{f700}")
    precondition(editor.focusedControl === name)
    pressSettingsKey(editor, 36, "\r")
    precondition(editor.isEditingText)
    editor.focus(name)
    let composing = name.currentEditor() as! NSTextView
    composing.setMarkedText("测", selectedRange: NSRange(location: 1, length: 0), replacementRange: composing.selectedRange())
    precondition(!editor.handleKeyDown(settingsKey(53, "\u{1b}")))
    precondition(!editor.handleKeyDown(settingsKey(36, "\r")))
    precondition(!editor.handleKeyDown(settingsKey(48, "\t")), "Input-method composition must retain navigation keys")
    composing.unmarkText()
    replaceSettingsText(name, with: "Edited with Keyboard")
    pressSettingsKey(editor, 48, "\t")
    precondition(editor.focusedControl === destination)
    replaceSettingsText(destination, with: "https://example.com/keyboard")
    pressSettingsKey(editor, 48, "\t", modifiers: .shift)
    precondition(editor.focusedControl === name)
    renderSettingsKeyboardPreview(editor, name: "editor", window: sheet)
    editor.showActions()
    renderSettingsKeyboardPreview(editor, name: "editor-actions", window: sheet)
    precondition(editor.bounds.contains(editor.actionsPopover!.frame), "Actions must fit even in the compact editor")
    pressSettingsKey(editor, 53, "\u{1b}")
    precondition(editor.isEditingText && window.attachedSheet === sheet, "Dismissing Actions must preserve text editing")
    pressSettingsKey(editor, 36, "\r", modifiers: .command)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    precondition(window.attachedSheet == nil && store.links[1].name == "Edited with Keyboard")
    precondition(store.links[1].link == "https://example.com/keyboard" && window.firstResponder === table)
    pressSettingsKey(keyboard, 45, "n", modifiers: .command)
    let blankEditor = window.attachedSheet!.contentView as! SettingsKeyboardView
    pressSettingsKey(blankEditor, 53, "\u{1b}")
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    precondition(window.attachedSheet == nil && store.links.count == 2)
    pressSettingsKey(keyboard, 51, "\u{7f}", modifiers: .command)
    precondition(store.links.count == 1 && store.links[0].name == "First")
}

@MainActor
private func checkScriptKeyboard(_ keyboard: SettingsKeyboardView, store: ScriptCommandStore) {
    pressSettingsKey(keyboard, 20, "3", modifiers: .command)
    let settings = settingsViews(keyboard).compactMap { $0 as? ScriptSettingsView }.first!
    waitForSettingsScripts(settings)
    precondition(settings.discovery.commands.count == 1)
    let folders = keyboard.focusedControl
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(keyboard.focusedControl?.accessibilityLabel() == "Script Commands")
    pressSettingsKey(keyboard, 126, "\u{f700}")
    precondition(keyboard.focusedControl === folders, "Arrows must cross between folder and command lists")
    precondition(keyboard.visibleActions.contains { $0.title == "Create Script…" && $0.modifiers == [.command, .shift] })
    pressSettingsKey(keyboard, 15, "r", modifiers: .command)
    waitForSettingsScripts(settings)
    pressSettingsKey(keyboard, 51, "\u{7f}", modifiers: .command)
    waitForSettingsScripts(settings)
    precondition(store.directories.isEmpty && settings.discovery.commands.isEmpty)
}

@MainActor
private func waitForSettingsScripts(_ settings: ScriptSettingsView) {
    let deadline = Date().addingTimeInterval(10)
    while settings.isRefreshing && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    precondition(!settings.isRefreshing)
}

@MainActor
private func checkSettingsKeyboardPreviews(_ keyboard: SettingsKeyboardView, window: NSWindow) {
    for (index, key) in ["1", "2", "3", "4"].enumerated() {
        pressSettingsKey(keyboard, 18, key, modifiers: .command)
        for width: CGFloat in [700, 840] {
            window.setContentSize(NSSize(width: width, height: 560))
            renderSettingsKeyboardPreview(keyboard, name: "section-\(index)-\(Int(width))", window: window)
            keyboard.layoutSubtreeIfNeeded()
            precondition(keyboard.bounds.height == 560, "The action group must fit without increasing the window height")
            let group = keyboard.footer as! ActionGroupView
            precondition(keyboard.bounds.contains(group.frame))
            for button in settingsViews(group).compactMap({ $0 as? NSButton }) {
                let bounds = group.surface.convert(button.bounds, from: button)
                precondition(group.surface.bounds.insetBy(dx: -1, dy: -1).contains(bounds),
                             "Settings action buttons must fit their glass surface: \(button.accessibilityLabel() ?? "")")
            }
            keyboard.focus(keyboard.sidebarControl()!)
            renderSettingsKeyboardPreview(keyboard, name: "sidebar-\(index)-\(Int(width))", window: window)
            keyboard.enterContent()
            keyboard.showActions()
            renderSettingsKeyboardPreview(keyboard, name: "actions-\(index)-\(Int(width))", window: window)
            precondition(keyboard.bounds.contains(keyboard.actionsPopover!.frame), "Actions must stay inside Settings")
            keyboard.dismissActions()
        }
    }
}

@MainActor
private func renderSettingsKeyboardPreview(_ view: NSView, name: String, window: NSWindow) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_SETTINGS_PREVIEW_DIR"] else { return }
    for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        window.appearance = NSAppearance(named: appearance)
        if window.sheetParent == nil { AppearanceCheckWindows.show(window) }
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("settings-keyboard-\(name)-\(suffix).png"))
    }
}

@MainActor
private func replaceSettingsText(_ field: NSTextField, with text: String) {
    let editor = field.currentEditor() as! NSTextView
    editor.selectAll(nil)
    editor.insertText(text, replacementRange: editor.selectedRange())
    precondition(field.stringValue == text)
}

@MainActor
private func settingsViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(settingsViews) }

@MainActor
private func pressSettingsKey(_ view: SettingsKeyboardView, _ code: UInt16, _ characters: String,
                              modifiers: NSEvent.ModifierFlags = []) {
    precondition(view.handleKeyDown(settingsKey(code, characters, modifiers: modifiers)), "Settings must handle \(code) \(characters)")
}

private func settingsKey(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = [],
                         isRepeat: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: isRepeat, keyCode: code)!
}

@MainActor
private func checkSettingsActionsPopover(_ keyboard: SettingsKeyboardView, window: NSWindow) {
    let originalActions = keyboard.actions
    let originalFocus = keyboard.focusedControl
    let windowCount = NSApp.windows.count
    var choices: [String] = []
    keyboard.actions = {
        [SettingsAction("Unavailable", isEnabled: false) { choices.append("disabled") },
         SettingsAction("First Action", key: "f") { choices.append("first") },
         SettingsAction("Second Action", key: "s") { choices.append("second") }]
    }
    defer { keyboard.dismissActions(); keyboard.actions = originalActions }
    keyboard.showActions()
    let popover = keyboard.actionsPopover!
    keyboard.layoutSubtreeIfNeeded()
    precondition(popover.superview === keyboard && NSApp.windows.count == windowCount,
                 "Actions must render inside Settings without creating another window")
    precondition(keyboard.bounds.contains(popover.frame) && popover.frame.minY >= keyboard.footer.frame.maxY)
    precondition(popover.selectedIndex == 1, "Actions must skip a disabled first entry")
    checkPopoverMaterialAndAnimation(popover, keyboard: keyboard)
    let shortcutHints = settingsViews(popover).compactMap { $0 as? KeyboardHintView }
    precondition(shortcutHints.count == 2, "Popover shortcuts must use the shared keyboard-hint component")
    pressSettingsKey(keyboard, 125, "\u{f701}")
    precondition(popover.selectedIndex == 2 && keyboard.focusedControl === originalFocus)
    pressSettingsKey(keyboard, 126, "\u{f700}")
    precondition(popover.selectedIndex == 1)
    precondition(keyboard.handleKeyDown(settingsKey(36, "\r", isRepeat: true)))
    precondition(choices.isEmpty && keyboard.actionsPopover === popover)
    pressSettingsKey(keyboard, 36, "\r")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(shortcutHints[0].isKeyPressed && popover.isDismissing,
                     "Running an action must light its shared keycap during the closing animation")
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    precondition(popover.superview == nil && !popover.isTransitioning, "The closing animation must remove its view")
    precondition(choices == ["first"] && keyboard.actionsPopover == nil && keyboard.focusedControl === originalFocus)
    keyboard.showActions()
    let row = settingsViews(keyboard.actionsPopover!).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Second Action" }!
    row.performClick(nil)
    precondition(choices == ["first", "second"] && keyboard.actionsPopover == nil)
    keyboard.showActions()
    pressSettingsKey(keyboard, 53, "\u{1b}")
    precondition(keyboard.actionsPopover == nil && window.isVisible && keyboard.focusedControl === originalFocus)
    keyboard.showActions()
    pressSettingsKey(keyboard, 40, "k", modifiers: .command)
    precondition(keyboard.actionsPopover == nil)
    keyboard.showActions()
    let point = keyboard.convert(NSPoint(x: 12, y: 12), to: nil)
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    precondition(keyboard.dismissActionsOutside(click) && keyboard.actionsPopover == nil && choices.count == 2)
    precondition(!window.isKeyWindow, "Popover checks must preserve the user's keyboard focus")
    print("PASS: Actions stays inside Settings, skips disabled rows, supports arrows/Return/clicks, and dismisses with Escape, Command–K, or an outside click")
}

@MainActor
private func checkPopoverMaterialAndAnimation(_ popover: SettingsActionsPopover, keyboard: SettingsKeyboardView) {
    if #available(macOS 26.0, *) {
        let glass = settingsViews(popover).compactMap { $0 as? NSGlassEffectView }.first!
        precondition(glass.style == .regular && glass.tintColor == nil && glass.contentView is NSScrollView,
                     "Actions must use native, untinted regular Liquid Glass")
    }
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(popover.isTransitioning && popover.alphaValue < 1)
        precondition(popover.frame.minY <= popover.targetFrame.minY)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    precondition(!popover.isTransitioning && popover.alphaValue == 1 && popover.frame == popover.targetFrame,
                 "Opening must settle at the anchored frame with native glass geometry")
    precondition(SettingsActionsPopover.transitionDuration(appearing: true, reduceMotion: true) == 0)
    precondition(SettingsActionsPopover.transitionDuration(appearing: false, reduceMotion: true) == 0)
    let immediate = SettingsActionsPopover(actions: [])
    keyboard.addSubview(immediate)
    immediate.setTargetFrame(NSRect(x: 24, y: 80, width: 200, height: 48))
    immediate.present(animated: false)
    precondition(!immediate.isTransitioning && immediate.alphaValue == 1)
    var removed = false
    immediate.dismiss(animated: false) { immediate.removeFromSuperview(); removed = true }
    precondition(removed && !immediate.isTransitioning && immediate.superview == nil)
    print("PASS: native Liquid Glass, anchored fade/slide transitions, shared shortcut keycaps, and immediate Reduce Motion behavior")
}
