import AppKit

@MainActor
final class ScriptCommandView: NSView, NSTextFieldDelegate {
    private let command: ScriptCommand
    private let runner = ScriptRunner()
    private var inputs: [NSControl] = []
    private let status = Appearance.label("Ready to run", size: 12)
    private let output = NSTextView()
    private let runButton = NSButton(title: "Run Script", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy Output", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private var task: Task<Void, Never>?
    private(set) var isRunning = false
    private(set) var result: ScriptRunResult?
    var onClose: (() -> Void)?
    var onSilentSuccess: (() -> Void)?

    init(command: ScriptCommand) {
        self.command = command
        super.init(frame: .zero)
        configureLayout()
        setAccessibilityLabel("Script command: \(command.name)")
    }

    required init?(coder: NSCoder) { fatalError("Use init(command:)") }
    override var acceptsFirstResponder: Bool { true }

    func begin() {
        if command.arguments.isEmpty && !command.needsConfirmation { runScript() }
        else { window?.makeFirstResponder(inputs.first ?? runButton) }
    }

    private func configureLayout() {
        let title = Appearance.label(command.name, size: 19, weight: .semibold, color: .labelColor)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.toolTip = command.description.isEmpty ? command.url.path : command.description
        let header = Appearance.stack([Appearance.symbol("terminal", size: 22, color: .labelColor), title, Appearance.spacer()], spacing: 12)
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        for argument in command.arguments { addArgument(argument, to: form) }
        if command.needsConfirmation {
            runButton.title = "Confirm & Run"
        }
        form.isHidden = form.arrangedSubviews.isEmpty
        let scroll = makeOutput()
        configureButtons()
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        status.setAccessibilityIdentifier("scriptStatus")
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.lineBreakMode = .byTruncatingTail
        let footer = Appearance.stack([backButton, progress, status, Appearance.spacer(), copyButton, runButton], spacing: 10)
        let content = NSStackView(views: [header, form, scroll, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        for child in content.arrangedSubviews { child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
    }

    private func addArgument(_ argument: ScriptCommand.Argument, to form: NSStackView) {
        let input: NSControl
        if argument.type == .dropdown {
            let popup = NSPopUpButton()
            if argument.optional { popup.addItem(withTitle: "None") }
            for option in argument.data { popup.addItem(withTitle: option.title) }
            input = popup
        } else {
            let field = argument.type == .password ? NSSecureTextField() : NSTextField()
            field.placeholderString = argument.placeholder
            field.delegate = self
            input = field
        }
        input.setAccessibilityLabel(argument.placeholder)
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inputs.append(input)
        let label = Appearance.label(argument.placeholder + (argument.optional ? " (optional)" : ""), size: 12)
        label.lineBreakMode = .byTruncatingTail
        label.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let row = Appearance.stack([label, input], spacing: 12)
        form.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
    }

    private func makeOutput() -> NSScrollView {
        output.isEditable = false
        output.isSelectable = true
        output.isRichText = false
        output.drawsBackground = false
        output.textColor = .labelColor
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        output.textContainerInset = NSSize(width: 12, height: 12)
        output.autoresizingMask = [.width]
        output.isVerticallyResizable = true
        output.textContainer?.widthTracksTextView = true
        output.setAccessibilityLabel("Script output")
        output.string = "Output will appear here."
        let scroll = NSScrollView()
        scroll.documentView = output
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.borderWidth = 0.5
        scroll.layer?.borderColor = NSColor.separatorColor.cgColor
        return scroll
    }

    private func configureButtons() {
        for button in [runButton, copyButton, backButton] { button.bezelStyle = .rounded; button.target = self }
        runButton.action = #selector(runScript)
        runButton.keyEquivalent = "\r"
        runButton.keyEquivalentModifierMask = []
        copyButton.action = #selector(copyOutput)
        copyButton.isEnabled = false
        backButton.action = #selector(close)
        backButton.keyEquivalent = "\u{1b}"
        backButton.keyEquivalentModifierMask = []
    }

    private var values: [String] {
        zip(command.arguments, inputs).map { argument, input in
            guard let popup = input as? NSPopUpButton else { return input.stringValue }
            let index = popup.indexOfSelectedItem - (argument.optional ? 1 : 0)
            return argument.data.indices.contains(index) ? argument.data[index].value : ""
        }
    }

    @objc func runScript() {
        guard !isRunning, result == nil else { return }
        let arguments = values
        do { _ = try command.preparedArguments(arguments) }
        catch { status.stringValue = error.localizedDescription; return }
        isRunning = true
        runButton.isEnabled = false
        inputs.forEach { $0.isEnabled = false }
        backButton.title = "Cancel"
        status.stringValue = "Running…"
        output.string = ""
        progress.startAnimation(nil)
        task = Task { [weak self] in
            guard let self else { return }
            do { finish(try await runner.run(command, values: arguments)) }
            catch { finishError(error) }
        }
    }

    private func finish(_ result: ScriptRunResult) {
        self.result = result
        finishRunning()
        let statuses = [(result.cancelled, "Cancelled"), (result.timedOut, "Stopped after 60 seconds"),
                        (result.succeeded, "Completed")]
        status.stringValue = statuses.first(where: { $0.0 })?.1 ?? "Failed · Exit code \(result.exitCode)"
        let text = command.mode == .compact && result.succeeded
            ? result.output.components(separatedBy: .newlines).last(where: { !$0.isEmpty }) ?? ""
            : result.output
        output.string = text.isEmpty ? (result.succeeded ? "Script completed without output." : "The script did not produce output.") : text
        copyButton.isEnabled = !result.output.isEmpty
        if command.mode == .silent && result.succeeded { onSilentSuccess?() }
    }

    private func finishError(_ error: Error) {
        finishRunning()
        status.stringValue = "Couldn’t run script"
        output.string = error.localizedDescription
    }

    private func finishRunning() {
        isRunning = false
        task = nil
        progress.stopAnimation(nil)
        backButton.title = "Back"
        backButton.isEnabled = true
        window?.makeFirstResponder(self)
    }

    @objc private func copyOutput() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.output, forType: .string)
    }

    @objc private func close() {
        if isRunning { runner.cancel(); backButton.isEnabled = false; return }
        onClose?()
    }

    func cancel() { task?.cancel(); runner.cancel() }
    override func cancelOperation(_ sender: Any?) { close() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) { runScript(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
}
