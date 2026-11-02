import AppKit
import Carbon

// Carbon's registered hot keys do not require Accessibility or Input Monitoring access.
final class LauncherHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void
    private let shortcut: LauncherShortcut
    private(set) var isRegistered = false

    init(shortcut: LauncherShortcut = .commandSpace, onPress: @escaping () -> Void) {
        self.onPress = onPress
        self.shortcut = shortcut
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<LauncherHotKey>.fromOpaque(context).takeUnretainedValue().onPress()
            return noErr
        }, 1, &event, context, &handler)
        guard result == noErr else { return }
        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            isRegistered = false
            return
        }
        guard hotKey == nil, handler != nil, shortcut.isValid else { return }
        let identifier = EventHotKeyID(signature: OSType(0x464C4E54), id: 1)
        isRegistered = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

extension LauncherShortcut {
    var menuModifiers: NSEvent.ModifierFlags {
        let pairs: [(ShortcutModifiers, NSEvent.ModifierFlags)] = [
            (.command, .command), (.option, .option), (.control, .control), (.shift, .shift)
        ]
        return pairs.reduce([]) { modifiers.contains($1.0) ? $0.union($1.1) : $0 }
    }

    fileprivate var carbonModifiers: UInt32 {
        let pairs: [(ShortcutModifiers, UInt32)] = [
            (.command, UInt32(cmdKey)), (.option, UInt32(optionKey)),
            (.control, UInt32(controlKey)), (.shift, UInt32(shiftKey))
        ]
        return pairs.reduce(0) { modifiers.contains($1.0) ? $0 | $1.1 : $0 }
    }
}
