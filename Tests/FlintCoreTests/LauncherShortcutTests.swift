import Foundation
import Testing
@testable import FlintCore

struct LauncherShortcutTests {
    @Test func customCombinationSurvivesEncoding() throws {
        let shortcut = LauncherShortcut(keyCode: 40, modifiers: [.control, .option, .shift, .command], characters: "K")
        #expect(shortcut.isValid)
        #expect(shortcut.title == "⌃⌥⇧⌘K")
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(LauncherShortcut.self, from: data) == shortcut)
    }

    @Test func ordinaryTypingAndShiftOnlyAreRejected() {
        #expect(!LauncherShortcut(keyCode: 40, modifiers: [], characters: "k").isValid)
        #expect(!LauncherShortcut(keyCode: 40, modifiers: .shift, characters: "K").isValid)
    }

    @Test func functionKeysWorkWithoutModifiers() {
        let shortcut = LauncherShortcut(keyCode: 97, modifiers: [], characters: "\u{F709}")
        #expect(shortcut.isValid)
        #expect(shortcut.title == "F6")
    }

    @Test func escapeModifierKeysAndMalformedValuesAreRejected() {
        #expect(!LauncherShortcut(keyCode: 53, modifiers: .command, characters: "\u{1b}").isValid)
        #expect(!LauncherShortcut(keyCode: 55, modifiers: .command, characters: "x").isValid)
        #expect(!LauncherShortcut(keyCode: 200, modifiers: .command, characters: "x").isValid)
        #expect(!LauncherShortcut(keyCode: 40, modifiers: .command, characters: "").isValid)
        #expect(!LauncherShortcut(keyCode: 40, modifiers: [.command, ShortcutModifiers(rawValue: 128)], characters: "k").isValid)
    }
}
