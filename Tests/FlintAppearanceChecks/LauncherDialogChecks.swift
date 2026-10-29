import AppKit

@MainActor
func checkLauncherDialog() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let surface = Appearance.launcherSurface(content: NSView(frame: window.contentView!.bounds))
    Appearance.setLauncherCornerRadius(LauncherLayout.cornerRadius, on: surface)
    window.contentView = surface
    var responses: [Int] = []
    let dialog = LauncherDialogView(title: "Empty Trash?", message: "Permanently delete items?",
                                    buttonTitles: ["Cancel", "Empty Trash"]) { responses.append($0) }
    dialog.frame = surface.bounds
    surface.addSubview(dialog)
    surface.layoutSubtreeIfNeeded()
    precondition(window.firstResponder === dialog)
    precondition(dialog.superview === surface && surface.layer!.masksToBounds)
    precondition(surface.layer!.cornerRadius == LauncherLayout.cornerRadius)
    for keyCode: UInt16 in [48, 123, 124, 49] {
        dialog.keyDown(with: dialogKeyEvent(keyCode))
        precondition(responses.isEmpty && window.firstResponder === dialog && window.defaultButtonCell == nil)
    }
    dialog.keyDown(with: dialogKeyEvent(48, modifiers: .shift))
    precondition(responses.isEmpty && window.defaultButtonCell == nil)
    dialog.keyDown(with: dialogKeyEvent(53))
    precondition(responses.isEmpty && dialogHint(in: dialogButtons(in: dialog)[0]).isKeyPressed)
    precondition(!dialogButtons(in: dialog)[0].isHighlighted)
    dialog.keyUp(with: dialogKeyEvent(53, type: .keyUp))
    precondition(responses == [0] && dialog.superview == nil && window.defaultButtonCell == nil)
    dialog.insertNewline(nil)
    precondition(responses == [0])
    let confirm = LauncherDialogView(title: "Confirm", message: "Simulated action",
                                     buttonTitles: ["Cancel", "Confirm"]) { responses.append($0) }
    surface.addSubview(confirm)
    confirm.keyUp(with: dialogKeyEvent(36, type: .keyUp))
    confirm.keyDown(with: dialogKeyEvent(36, isRepeat: true))
    precondition(responses == [0])
    confirm.keyDown(with: dialogKeyEvent(53))
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    confirm.keyUp(with: dialogKeyEvent(53, type: .keyUp))
    precondition(responses == [0] && !dialogHint(in: dialogButtons(in: confirm)[0]).isKeyPressed)
    confirm.keyDown(with: dialogKeyEvent(36))
    confirm.keyDown(with: dialogKeyEvent(36, isRepeat: true))
    confirm.keyUp(with: dialogKeyEvent(76, type: .keyUp))
    precondition(responses == [0] && dialogHint(in: dialogButtons(in: confirm)[1]).isKeyPressed)
    confirm.keyUp(with: dialogKeyEvent(36, type: .keyUp))
    precondition(responses == [0, 1])
    let acknowledgement = LauncherDialogView(title: "Error", message: "Simulated error",
                                             buttonTitles: ["OK"]) { responses.append($0) }
    surface.addSubview(acknowledgement)
    acknowledgement.keyDown(with: dialogKeyEvent(76))
    precondition(responses == [0, 1])
    acknowledgement.keyUp(with: dialogKeyEvent(76, type: .keyUp))
    precondition(responses == [0, 1, 0])
    print("PASS: dialog dimming is inside the clipped launcher surface")
    print("PASS: Return confirms, Escape cancels, and keypad Enter acknowledges; each responds exactly once")
    print("PASS: Tab, Shift-Tab, arrows and Space do not select or activate dialog buttons")
    print("PASS: dialog buttons press on key down, activate on matching release, and cancel presses on focus loss")
    print("PASS: held keys, repeats and unmatched releases cannot confirm a newly opened dialog")
}

@MainActor
private func dialogKeyEvent(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [],
                            type: NSEvent.EventType = .keyDown, isRepeat: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: isRepeat, keyCode: keyCode)!
}

@MainActor
private func dialogButtons(in view: NSView) -> [NSButton] {
    if let button = view as? NSButton { return [button] }
    return view.subviews.flatMap { dialogButtons(in: $0) }
}

@MainActor
private func dialogHint(in button: NSButton) -> KeyboardHintView {
    button.subviews.first { $0 is KeyboardHintView } as! KeyboardHintView
}

@MainActor
func checkKeyboardHintFeedback() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let hint = KeyboardHintView(.returnKey, label: "Confirm")
    window.contentView!.addSubview(hint)
    hint.setFrameSize(hint.intrinsicContentSize)
    hint.layoutSubtreeIfNeeded()
    let initialSize = hint.intrinsicContentSize
    let imageView = hint.subviews[0] as! NSImageView
    let initialFrame = imageView.frame
    let releasedImage = imageView.image!.tiffRepresentation
    let background = hint.layer!.sublayers!.first { $0.name == "keyboardHintPressBackground" }!
    let initialBackgroundFrame = background.frame
    var releases = 0
    hint.onKeyRelease = { releases += 1 }
    hint.handleKeyEvent(dialogKeyEvent(36))
    precondition(hint.isKeyPressed && releases == 0 && hint.intrinsicContentSize == initialSize)
    precondition(imageView.image!.tiffRepresentation == releasedImage && imageView.frame == initialFrame)
    precondition(background.opacity == 1 && background.frame == initialBackgroundFrame)
    checkHintAnimation(background, to: 1)
    hint.handleKeyEvent(dialogKeyEvent(36, isRepeat: true))
    hint.handleKeyEvent(dialogKeyEvent(53, type: .keyUp))
    precondition(hint.isKeyPressed && releases == 0)
    hint.handleKeyEvent(dialogKeyEvent(36, type: .keyUp))
    hint.handleKeyEvent(dialogKeyEvent(36, type: .keyUp))
    precondition(!hint.isKeyPressed && releases == 1)
    precondition(background.opacity == 0 && imageView.frame == initialFrame && hint.intrinsicContentSize == initialSize)
    checkHintAnimation(background, to: 0)
    hint.handleKeyEvent(dialogKeyEvent(76))
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    hint.handleKeyEvent(dialogKeyEvent(76, type: .keyUp))
    precondition(!hint.isKeyPressed && releases == 1)
    hint.handleKeyEvent(dialogKeyEvent(36))
    hint.removeFromSuperview()
    precondition(!hint.isKeyPressed)
    hint.hint = .command
    hint.handleKeyEvent(dialogKeyEvent(55, modifiers: .command, type: .flagsChanged))
    precondition(hint.isKeyPressed)
    hint.handleKeyEvent(dialogKeyEvent(55, type: .flagsChanged))
    precondition(!hint.isKeyPressed)
    print("PASS: hint backgrounds fade on press and release while symbols, labels, outlines and layout stay unchanged")
    print("PASS: keyboard hint state resets on release, focus loss or removal")
}

@MainActor
private func checkHintAnimation(_ layer: CALayer, to opacity: Float) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(layer.animation(forKey: "press") == nil)
        return
    }
    let animation = layer.animation(forKey: "press") as! CABasicAnimation
    precondition(animation.keyPath == "opacity" && animation.duration > 0)
    precondition((animation.toValue as! NSNumber).floatValue == opacity)
}

@MainActor
func checkLauncherRowIcons() {
    let cell = ApplicationRowContent(frame: NSRect(x: 0, y: 0, width: 760, height: LauncherLayout.resultRowHeight))
    let row = cell.subviews[0] as! NSStackView
    let slot = row.arrangedSubviews[0]
    let icon = slot.subviews[0] as! NSImageView
    let app = ApplicationRecord(name: "Finder", bundleIdentifier: "com.apple.finder",
                                url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
    cell.configure(item: .action(.emptyTrash), icon: NSImage(), selected: true)
    cell.layoutSubtreeIfNeeded()
    precondition(icon.frame.size == NSSize(width: 18, height: 18))
    precondition(slot.frame.width == 28 && icon.frame.midX == slot.bounds.midX)
    cell.configure(item: .application(app), icon: NSImage(), selected: false)
    cell.layoutSubtreeIfNeeded()
    precondition(icon.frame.size == NSSize(width: 28, height: 28))
    print("PASS: action icons use 18 points; reused application rows restore 28 points without shifting text")
}
