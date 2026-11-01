import AppKit

extension SettingsKeyboardView {
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard window?.attachedSheet == nil, trackingMenus.isEmpty else { return false }
        if let actionsPopover { return actionsPopover.handleKeyDown(event) }
        if isRecording() { return leaveRecordingWithTab(event) }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if let editor = window?.firstResponder as? NSTextView, editor.hasMarkedText(), !modifiers.contains(.command) {
            return false
        }
        if event.keyCode == 53 && event.isARepeat { return true }
        if event.keyCode == 53 && modifiers.isEmpty && isEditingText { finishTextEditing(); return true }
        if event.keyCode == 51 && isEditingText { return false }
        if handleShortcut(event, modifiers: modifiers) { return true }
        guard modifiers.intersection([.command, .option, .control]).isEmpty else { return false }
        if beginTyping(event) { return false }
        usesKeyboard = true
        return handleNavigation(event, backwards: modifiers.contains(.shift))
    }

    private func beginTyping(_ event: NSEvent) -> Bool {
        guard !isEditingText, let field = focusedControl as? NSTextField,
              let text = event.characters, !text.isEmpty else { return false }
        let printable = text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
        guard printable else { return false }
        focus(field)
        return true
    }

    func handleMenuTracking(_ notification: Notification) -> Bool {
        guard let menu = notification.object as? NSMenu else { return false }
        let identifier = ObjectIdentifier(menu)
        if notification.name == NSMenu.didBeginTrackingNotification {
            trackingMenus.insert(identifier)
        } else {
            trackingMenus.remove(identifier)
        }
        return true
    }

    private func leaveRecordingWithTab(_ event: NSEvent) -> Bool {
        guard event.keyCode == 48, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        cancelRecording()
        moveFocus(backwards: event.modifierFlags.contains(.shift))
        return true
    }

    private func handleShortcut(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "k" {
            if !event.isARepeat { showActions() }
            return true
        }
        guard let action = actions().first(where: { $0.matches(event) }) else { return false }
        if action.isEnabled && !event.isARepeat { action.perform() }
        refreshActions()
        return true
    }

    private func handleNavigation(_ event: NSEvent, backwards: Bool) -> Bool {
        if event.keyCode == 48 { moveFocus(backwards: backwards); return true }
        if event.keyCode == 53 { navigateBack(); return true }
        if [125, 126].contains(event.keyCode) { return moveArrowSelection(by: event.keyCode == 125 ? 1 : -1) }
        if [123, 124].contains(event.keyCode) { return handleHorizontalArrow(right: event.keyCode == 124) }
        if event.keyCode == 49 { return activateWithSpace(event) }
        guard [36, 76].contains(event.keyCode) else { return false }
        if !event.isARepeat { activateFocusedControl() }
        refreshActions()
        return true
    }

    private func activateWithSpace(_ event: NSEvent) -> Bool {
        guard !(focusedControl is NSTextField), !(focusedControl is NSTableView) else { return false }
        if !event.isARepeat { activateFocusedControl() }
        return true
    }

}
