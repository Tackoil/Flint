import AppKit

@MainActor
func checkScriptCommands() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Flint Script UI \(UUID())")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "FlintScriptUI.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let store = ScriptCommandStore(defaults: defaults)
    store.add(directory)
    let source = """
    #!/bin/bash
    # @raycast.schemaVersion 1
    # @raycast.title Greet Team
    # @raycast.mode fullOutput
    # @raycast.description Print a greeting using the supplied name and environment.
    # @raycast.argument1 {"type":"text","placeholder":"Name"}
    # @raycast.argument2 {"type":"password","placeholder":"Token","optional":true}
    # @raycast.argument3 {"type":"dropdown","placeholder":"Environment","data":[{"title":"Development","value":"dev"},{"title":"Production","value":"prod"}]}
    printf 'Hello, %s!\\nEnvironment: %s\\n' "$1" "$3"
    """
    try! source.write(to: directory.appendingPathComponent("greet.sh"), atomically: true, encoding: .utf8)
    let controller = ApplicationsViewController(scriptStore: store)
    let window = AppearanceCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    defer { controller.cancelScript(); window.orderOut(nil) }
    let search = scriptDescendants(controller.view).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    let table = scriptDescendants(controller.view).compactMap { $0 as? NSTableView }.first!
    var settingsRequests = 0
    controller.onShowScriptSettings = { settingsRequests += 1 }
    search.stringValue = "Script Commands"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(settingsRequests == 1)
    search.stringValue = "Greet Team"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    waitForScriptUI { table.numberOfRows == 1 }
    _ = controller.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    precondition(controller.isPresentingScript && controller.displayMode == .results)
    let panel = scriptDescendants(controller.view).compactMap { $0 as? ScriptCommandView }.first!
    let fields = scriptDescendants(panel).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    precondition(fields.count == 2 && fields[1] is NSSecureTextField)
    panel.runScript()
    precondition(!panel.isRunning && panel.result == nil, "Required arguments must block execution")
    fields[0].stringValue = "Flint 你好"
    let dropdown = scriptDescendants(panel).compactMap { $0 as? NSPopUpButton }.first!
    dropdown.selectItem(at: 1)
    renderScriptPreview(controller.view, window: window, name: "script-arguments")
    panel.runScript()
    waitForScriptUI { panel.result != nil }
    precondition(panel.result!.succeeded && panel.result!.output == "Hello, Flint 你好!\nEnvironment: prod\n")
    renderScriptPreview(controller.view, window: window, name: "script-output")
    panel.cancelOperation(nil)
    precondition(!controller.isPresentingScript && search.stringValue == "Greet Team")
    checkScriptModes(directory: directory, window: window)
    checkScriptSettings(store: store, directory: directory, window: window)
    print("PASS: script discovery, launcher activation, required/password/dropdown arguments, Unicode output, Back, confirmation, modes, cancellation, and Settings")
}

@MainActor
private func checkScriptSettings(store: ScriptCommandStore, directory: URL, window: NSWindow) {
    let second = directory.appendingPathComponent("open-project.sh")
    try! ScriptCommandStore.template.replacingOccurrences(of: "Hello World", with: "Open Project")
        .write(to: second, atomically: true, encoding: .utf8)
    let controller = SettingsViewController(preferences: LauncherPreferences(), onShortcutChange: { _ in true },
                                             onRecordingStateChange: { _ in }, onMenuBarVisibilityChange: { _ in },
                                             scriptStore: store)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 720, height: 560))
    controller.showScriptSettings()
    let settings = scriptDescendants(controller.view).compactMap { $0 as? ScriptSettingsView }.first!
    waitForScriptUI { !settings.isRefreshing && settings.discovery.commands.count == 2 }
    let tables = scriptDescendants(settings).compactMap { $0 as? NSTableView }
    let folders = tables.first { $0.accessibilityLabel() == "Script Folders" }!
    let commands = tables.first { $0.accessibilityLabel() == "Script Commands" }!
    precondition(folders.numberOfRows == 1 && commands.numberOfRows == 2)
    let remove = scriptDescendants(settings).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Remove Script Folder" }!
    precondition(!remove.isEnabled)
    folders.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    precondition(remove.isEnabled)
    renderScriptPreview(controller.view, window: window, name: "script-settings")
    let labels = scriptDescendants(settings).compactMap { $0 as? NSTextField }.map(\.stringValue)
    precondition(!labels.contains(where: { $0.contains("Raycast") || $0.contains("script commands ·") || $0 == "greet.sh" }))
    let invalid = directory.appendingPathComponent("invalid.sh")
    try! "not a script command".write(to: invalid, atomically: true, encoding: .utf8)
    settings.reload()
    waitForScriptUI { !settings.isRefreshing && settings.discovery.issues.count == 1 }
    let issues = scriptDescendants(settings).compactMap { $0 as? NSButton }.first { $0.title == "1 Issue…" }!
    precondition(!issues.isHidden && folders.selectedRow == 0)
    renderScriptPreview(controller.view, window: window, name: "script-settings-issues")
    remove.performClick(nil)
    waitForScriptUI { !settings.isRefreshing && settings.discovery.commands.isEmpty }
    precondition(store.directories.isEmpty && folders.numberOfRows == 0 && commands.numberOfRows == 0)
    precondition(!remove.isEnabled && issues.isHidden)
    precondition(FileManager.default.fileExists(atPath: second.path))
    renderScriptPreview(controller.view, window: window, name: "script-settings-empty")
}

@MainActor
private func checkScriptModes(directory: URL, window: NSWindow) {
    for (mode, body) in [("compact", "printf 'First\\nLast\\n'"), ("silent", "echo done"),
                         ("fullOutput", "echo failure >&2; exit 4")] {
        let source = "#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.title Mode Test\n# @raycast.mode \(mode)\n\(body)"
        let url = directory.appendingPathComponent("mode.sh")
        try! source.write(to: url, atomically: true, encoding: .utf8)
        let panel = ScriptCommandView(command: try! ScriptCommand.parse(source, url: url))
        window.contentView = panel
        panel.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        var dismissed = false
        panel.onSilentSuccess = { dismissed = true }
        panel.begin()
        waitForScriptUI { panel.result != nil }
        precondition(dismissed == (mode == "silent"))
        if mode == "compact" {
            let output = scriptDescendants(panel).compactMap { $0 as? NSTextView }.first!
            precondition(output.string == "Last")
        }
        if mode == "fullOutput" { precondition(panel.result!.exitCode == 4 && panel.result!.output.contains("failure")) }
        try! FileManager.default.removeItem(at: url)
    }
    let source = "#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.title Confirm Test\n# @raycast.mode fullOutput\n# @raycast.needsConfirmation true\nexec /bin/sleep 30"
    let url = directory.appendingPathComponent("confirm.sh")
    try! source.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let panel = ScriptCommandView(command: try! ScriptCommand.parse(source, url: url))
    window.contentView = panel
    panel.begin()
    precondition(!panel.isRunning && panel.result == nil)
    panel.runScript()
    precondition(panel.isRunning)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    panel.cancelOperation(nil)
    waitForScriptUI { panel.result != nil }
    precondition(panel.result!.cancelled)
    let back = scriptDescendants(panel).compactMap { $0 as? NSButton }.first { $0.title == "Back" }!
    precondition(back.isEnabled)
}

@MainActor
private func renderScriptPreview(_ view: NSView, window: NSWindow, name: String) {
    guard let directory = ProcessInfo.processInfo.environment["FLINT_SCRIPT_PREVIEW_DIR"] else { return }
    for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        window.appearance = NSAppearance(named: appearance)
        AppearanceCheckWindows.show(window)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(suffix).png")
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        window.orderOut(nil)
    }
}

@MainActor
private func waitForScriptUI(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(10)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    precondition(condition(), "Script UI did not finish in time")
}

@MainActor
private func scriptDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(scriptDescendants)
}
