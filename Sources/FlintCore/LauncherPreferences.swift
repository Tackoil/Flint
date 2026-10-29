import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
    static let all: Self = [.command, .option, .control, .shift]

    var symbols: String {
        let ordered: [(Self, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return ordered.filter { contains($0.0) }.map(\.1).joined()
    }
}

struct LauncherShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
    let characters: String

    static let commandSpace = Self(keyCode: 49, modifiers: .command, characters: " ")
    static let optionSpace = Self(keyCode: 49, modifiers: .option, characters: " ")
    static let controlSpace = Self(keyCode: 49, modifiers: .control, characters: " ")

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]
    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 71: "Clear", 76: "⌤", 114: "Help",
        115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    private static let unsupportedKeys: Set<UInt16> = [53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var title: String {
        let key = Self.specialKeys[keyCode] ?? Self.functionKeys[keyCode] ?? characters.uppercased()
        return modifiers.symbols + key
    }

    var isValid: Bool {
        guard keyCode <= 127, !Self.unsupportedKeys.contains(keyCode), characters.count == 1,
              modifiers.subtracting(.all).isEmpty else { return false }
        return !modifiers.intersection([.command, .option, .control]).isEmpty || Self.functionKeys[keyCode] != nil
    }
}

final class LauncherPreferences {
    private let defaults: UserDefaults
    private static let shortcutKey = "launcher.shortcut"
    private static let menuBarKey = "showInMenuBar"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showInMenuBar: Bool {
        get { defaults.object(forKey: Self.menuBarKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.menuBarKey) }
    }

    var shortcut: LauncherShortcut {
        get {
            if let data = defaults.data(forKey: Self.shortcutKey) {
                guard let shortcut = try? JSONDecoder().decode(LauncherShortcut.self, from: data),
                      shortcut.isValid else { return .commandSpace }
                return shortcut
            }
            let legacy: [String: LauncherShortcut] = [
                "commandSpace": .commandSpace, "optionSpace": .optionSpace, "controlSpace": .controlSpace
            ]
            return legacy[defaults.string(forKey: Self.shortcutKey) ?? ""] ?? .commandSpace
        }
        set {
            guard newValue.isValid, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.shortcutKey)
        }
    }
}
