import Foundation
import Testing
@testable import FlintCore

struct LauncherPreferencesTests {
    @Test func defaultShortcutIsCommandSpace() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LauncherPreferences(defaults: defaults).shortcut == .commandSpace)
    }

    @Test func selectionSurvivesCreatingANewPreferencesStore() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LauncherPreferences(defaults: defaults)
        preferences.shortcut = .optionSpace
        #expect(LauncherPreferences(defaults: defaults).shortcut == .optionSpace)
        preferences.shortcut = .controlSpace
        #expect(LauncherPreferences(defaults: defaults).shortcut == .controlSpace)
        preferences.shortcut = .commandSpace
        #expect(LauncherPreferences(defaults: defaults).shortcut == .commandSpace)
    }

    @Test func invalidSavedValueFallsBackToCommandSpace() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown-shortcut", forKey: "launcher.shortcut")
        #expect(LauncherPreferences(defaults: defaults).shortcut == .commandSpace)
    }

    @Test func customShortcutPersistsInANewDefaultsInstance() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcut = LauncherShortcut(keyCode: 40, modifiers: [.command, .option], characters: "k")
        LauncherPreferences(defaults: defaults).shortcut = shortcut
        let reloaded = try #require(UserDefaults(suiteName: suite))
        #expect(LauncherPreferences(defaults: reloaded).shortcut == shortcut)
    }

    @Test func legacyShortcutIsPreserved() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("optionSpace", forKey: "launcher.shortcut")
        let preferences = LauncherPreferences(defaults: defaults)
        #expect(preferences.shortcut == .optionSpace)
        preferences.shortcut = .commandSpace
        #expect(preferences.shortcut == .commandSpace)
        #expect(defaults.data(forKey: "launcher.shortcut") != nil)
    }

    @Test func invalidCustomShortcutDoesNotReplaceSavedChoice() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LauncherPreferences(defaults: defaults)
        preferences.shortcut = .optionSpace
        preferences.shortcut = LauncherShortcut(keyCode: 40, modifiers: [], characters: "k")
        #expect(preferences.shortcut == .optionSpace)
    }

    @Test func malformedStoredShortcutFallsBackToDefault() throws {
        let suite = "FlintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = LauncherShortcut(keyCode: 40, modifiers: [], characters: "k")
        defaults.set(try JSONEncoder().encode(invalid), forKey: "launcher.shortcut")
        #expect(LauncherPreferences(defaults: defaults).shortcut == .commandSpace)
        defaults.set(Data("invalid json".utf8), forKey: "launcher.shortcut")
        #expect(LauncherPreferences(defaults: defaults).shortcut == .commandSpace)
    }
}
