import Foundation
import PalpebraCore
import Testing

struct HotKeyComboTests {
    @Test func shortcutEncodingDisplayAndRecordingPolicy() throws {
        let encoded = Data(#"{"keyCode":15,"modifiers":2304}"#.utf8)
        let combo = try JSONDecoder().decode(HotKeyCombo.self, from: encoded)
        #expect(combo.display == "⌥⌘R")
        #expect(try JSONDecoder().decode(HotKeyCombo.self, from: JSONEncoder().encode(combo)) == combo)
        #expect(HotKeyCombo(keyCode: 0, modifiers: 6912).display == "⌃⌥⇧⌘A")
        #expect(HotKeyCombo(keyCode: 49, modifiers: 4096).display == "⌃Space")
        #expect(HotKeyCombo(keyCode: 999, modifiers: 256).display == "⌘Key999")
        #expect(HotKeyCombo.recordingAction(keyCode: 15, modifiers: 2304) == .combo(combo))
        #expect(HotKeyCombo.recordingAction(keyCode: 15, modifiers: 0) == .requiresModifier)
        #expect(HotKeyCombo.recordingAction(keyCode: 15, modifiers: 65536) == .requiresModifier)
        #expect(HotKeyCombo.recordingAction(keyCode: 53, modifiers: 0) == .cancel)
        #expect(HotKeyCombo.recordingAction(keyCode: 51, modifiers: 0) == .clear)
        #expect(HotKeyCombo.recordingAction(keyCode: 117, modifiers: 256) == .clear)
    }

    @Test func legacyShortcutMigratesOnceWithoutChangingOtherSettings() throws {
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"breakSeconds":180}"#.utf8), forKey: DefaultsKey.settings)
        defaults.set(Data(#"{"keyCode":15,"modifiers":2304}"#.utf8), forKey: "palpebra.restHotkey")

        let migrated = AppSettings.load(from: defaults)
        #expect(migrated.restHotkey == HotKeyCombo(keyCode: 15, modifiers: 2304))
        #expect(migrated.breakSeconds == 180)
        #expect(defaults.object(forKey: "palpebra.restHotkey") == nil)
        let stored = try #require(defaults.data(forKey: DefaultsKey.settings))
        #expect(try JSONDecoder().decode(AppSettings.self, from: stored) == migrated)
        #expect(AppSettings.load(from: defaults) == migrated)

        var cleared = migrated
        cleared.restHotkey = nil
        defaults.set(try JSONEncoder().encode(cleared), forKey: DefaultsKey.settings)
        #expect(AppSettings.load(from: defaults).restHotkey == nil)
    }

    @Test(arguments: [#"{"keyCode":0,"modifiers":256}"#, "null"])
    func currentShortcutChoiceWinsOverLegacy(choice: String) throws {
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let current = Data("{\"restHotkey\":\(choice)}".utf8)
        defaults.set(current, forKey: DefaultsKey.settings)
        defaults.set(Data(#"{"keyCode":15,"modifiers":2304}"#.utf8), forKey: "palpebra.restHotkey")
        let expected = try JSONDecoder().decode(AppSettings.self, from: current)
        #expect(AppSettings.load(from: defaults) == expected)
        #expect(defaults.object(forKey: "palpebra.restHotkey") == nil)
    }

    @Test func legacyClearedShortcutMigratesAlongsideV1Settings() throws {
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"usageThresholdMinutes":90}"#.utf8), forKey: "palpebra.settings.v1")
        defaults.set(Data("null".utf8), forKey: "palpebra.restHotkey")
        let migrated = AppSettings.load(from: defaults)
        #expect(migrated.usageThresholdMinutes == 90)
        #expect(migrated.restHotkey == nil)
        #expect(defaults.data(forKey: DefaultsKey.settings) != nil)
        #expect(defaults.object(forKey: "palpebra.restHotkey") == nil)
    }
}
