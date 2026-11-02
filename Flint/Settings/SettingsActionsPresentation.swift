import AppKit

extension SettingsKeyboardView {
    var visibleActions: [SettingsAction] { actions().filter(\.showsInMenu) }

    func showActions() {
        if actionsPopover != nil { dismissActions(); return }
        layoutSubtreeIfNeeded()
        let entries = visibleActions
        guard !entries.isEmpty else { return }
        let popover = SettingsActionsPopover(actions: entries)
        popover.onDismiss = { [weak self] in self?.dismissActions() }
        popover.onChoose = { [weak self] action in
            self?.dismissActions()
            action.perform()
            self?.refreshActions()
        }
        actionsPopover = popover
        addSubview(popover, positioned: .above, relativeTo: nil)
        layoutActionsPopover()
        popover.layoutSubtreeIfNeeded()
        popover.present()
        refreshActions()
    }

    func dismissActions(animated: Bool = true) {
        guard let popover = actionsPopover else { return }
        actionsPopover = nil
        popover.dismiss(animated: animated) { [weak popover] in popover?.removeFromSuperview() }
        refreshActions()
        if popover.superview === self { addSubview(popover, positioned: .above, relativeTo: nil) }
    }

    func layoutActionsPopover() {
        guard let actionsPopover else { return }
        let bottom = footer.frame.maxY + 8
        let availableHeight = max(0, bounds.maxY - 24 - bottom)
        let size = NSSize(width: min(actionsPopover.idealWidth, max(0, bounds.width - 48)),
                          height: min(actionsPopover.idealHeight, availableHeight))
        actionsPopover.setTargetFrame(NSRect(x: bounds.maxX - 24 - size.width, y: bottom,
                                             width: size.width, height: size.height))
        if subviews.last !== actionsPopover { addSubview(actionsPopover, positioned: .above, relativeTo: nil) }
    }

    func dismissActionsOutside(_ event: NSEvent) -> Bool {
        guard let actionsPopover else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard !actionsPopover.frame.contains(point) else { return false }
        dismissActions()
        return true
    }
}
