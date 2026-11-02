import AppKit

extension SettingsKeyboardView {
    var isEditingText: Bool { (window?.firstResponder as? NSTextView)?.isFieldEditor == true }
    var isInSidebar: Bool { focusedControl != nil && focusedControl === sidebarControl() }
    var availableNavigationControls: [NSView] {
        (navigationControls?() ?? controls()).filter {
            !$0.isHiddenOrHasHiddenAncestor && ($0 as? NSControl)?.isEnabled != false && $0 !== sidebarControl()
        }
    }

    func focus(_ control: NSView, keyboard: Bool = true, editing: Bool = true) {
        guard availableControls.contains(where: { $0 === control }) else { return }
        usesKeyboard = keyboard
        selectedControl = control
        if control !== sidebarControl() { lastContentControl = control }
        let responder = control is NSTextField && !editing ? self : control
        window?.makeFirstResponder(responder)
        if let table = control as? NSTableView, table.selectedRow < 0, table.numberOfRows > 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshActions()
    }

    func focusFirstControl() {
        guard let first = availableNavigationControls.first else { return }
        focus(first, editing: false)
    }

    func moveFocus(backwards: Bool) {
        let candidates = availableControls
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex { $0 === focusedControl }
        let origin = index ?? (backwards ? 0 : -1)
        focus(candidates[(origin + (backwards ? -1 : 1) + candidates.count) % candidates.count])
    }

    func enterContent() {
        let candidates = availableNavigationControls
        let remembered = candidates.first { $0 === lastContentControl }
        guard let control = remembered ?? candidates.first else { return }
        focus(control, editing: false)
    }

    func navigateBack() {
        if isEditingText { finishTextEditing(); return }
        if let sidebar = sidebarControl(), !isInSidebar {
            lastContentControl = focusedControl
            focus(sidebar, editing: false)
            return
        }
        onCancel()
    }

    func finishTextEditing() {
        guard let field = focusedControl as? NSTextField else { return }
        selectedControl = field
        window?.makeFirstResponder(self)
        refreshActions()
    }

    func moveArrowSelection(by offset: Int) -> Bool {
        guard !isEditingText, let control = focusedControl else { return false }
        if onSectionArrow?(control, offset) == true { return true }
        if let table = control as? NSTableView, moveTableSelection(table, by: offset) { return true }
        let candidates = availableNavigationControls
        guard !candidates.isEmpty else { return false }
        guard let index = candidates.firstIndex(where: { $0 === control }) else {
            if let row = logicalRowControl(for: control) { focus(row, editing: false) }
            return true
        }
        let next = min(max(index + offset, 0), candidates.count - 1)
        guard next != index else { return true }
        let target = candidates[next]
        focus(target, editing: false)
        selectTableEdge(target, movingDown: offset > 0)
        refreshActions()
        return true
    }

    private func logicalRowControl(for control: NSView) -> NSView? {
        var ancestor = control.superview
        while let view = ancestor {
            if view.identifier?.rawValue == "settingsRow" {
                return availableNavigationControls.first { $0.isDescendant(of: view) }
            }
            ancestor = view.superview
        }
        return availableNavigationControls.first
    }

    private func moveTableSelection(_ table: NSTableView, by offset: Int) -> Bool {
        let next = table.selectedRow < 0 ? 0 : table.selectedRow + offset
        guard (0..<table.numberOfRows).contains(next) else { return false }
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
        refreshActions()
        return true
    }

    private func selectTableEdge(_ control: NSView, movingDown: Bool) {
        guard let table = control as? NSTableView, table.numberOfRows > 0 else { return }
        let row = movingDown ? 0 : table.numberOfRows - 1
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func handleHorizontalArrow(right: Bool) -> Bool {
        guard !isEditingText else { return false }
        if right && isInSidebar { enterContent(); return true }
        if right, let field = focusedControl as? NSTextField { focus(field); return true }
        if !right, !isInSidebar, sidebarControl() != nil { navigateBack() }
        return true
    }

    func currentPrimaryAction() -> SettingsAction? {
        if isInSidebar { return SettingsAction("Open") { [weak self] in self?.enterContent() } }
        if let field = focusedControl as? NSTextField {
            if !isEditingText { return SettingsAction("Edit") { [weak self, weak field] in
                guard let field else { return }; self?.focus(field)
            } }
            if !editorActions.isEmpty { return SettingsAction("Done") { [weak self] in self?.finishTextEditing() } }
        }
        if let action = primaryAction(focusedControl) { return action }
        return controlAction()
    }

    private func controlAction() -> SettingsAction? {
        guard let control = focusedControl as? NSControl, control.action != nil else { return nil }
        let title = activationTitle(control)
        return SettingsAction(title, isEnabled: control.isEnabled) { [weak control] in
            guard let control, let action = control.action else { return }
            if let button = control as? NSButton { button.performClick(nil); return }
            if let toggle = control as? NSSwitch { toggle.state = toggle.state == .on ? .off : .on }
            control.sendAction(action, to: control.target)
        }
    }

    private func activationTitle(_ control: NSControl) -> String {
        if control is NSSwitch { return "Toggle" }
        if control is ShortcutRecorder { return "Record" }
        if control.accessibilityLabel() == "Open With" { return "Choose" }
        if control.action == NSSelectorFromString("removeKey") { return "Remove Key" }
        return "Activate"
    }
}
