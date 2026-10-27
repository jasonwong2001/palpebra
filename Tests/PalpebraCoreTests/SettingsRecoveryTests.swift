import Foundation
import PalpebraCore
import Testing

struct SettingsRecoveryTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func backups(in defaults: UserDefaults, for key: String) -> [Data] {
        defaults.dictionaryRepresentation().compactMap { name, value in
            name.hasPrefix("\(key).corrupt-") ? value as? Data : nil
        }
    }

    @Test(arguments: ["skipMode", "reminderStyle", "detectMode", "popupBackground", "miniBackground"])
    func futureEnumValuesOnlyResetTheirOwnField(key: String) throws {
        try withDefaults { defaults in
            var expected = AppSettings()
            expected.breakSeconds = 120
            expected.overlayText = "Keep my preferences"
            var document = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as? [String: Any])
            document[key] = "future-version-value"
            document["unknownFutureKey"] = ["value": true]
            defaults.set(try JSONSerialization.data(withJSONObject: document), forKey: DefaultsKey.settings)
            #expect(AppSettings.load(from: defaults) == expected)
            #expect(backups(in: defaults, for: DefaultsKey.settings).isEmpty)
        }
    }

    @Test(arguments: [
        "usageThresholdMinutes", "breakSeconds", "reminderIntervalMinutes", "skipMode", "reminderStyle",
        "preNotification", "screenTimeReminderEnabled", "screenTimePrimaryHours", "screenTimeSecondaryHours",
        "detectMode", "countVideoPlayback", "channels", "idleGraceSeconds", "popupBackground", "miniBackground",
        "overlayText", "overlayOpacity", "breakEndSound", "showDockIcon", "statusShowsFatigue", "statusShowsHours",
        "statusShowsMinutes", "statusShowsReminderCount", "restHotkey", "launchAtLogin",
    ])
    func wrongTypedFieldsOnlyResetTheirOwnValue(key: String) throws {
        try withDefaults { defaults in
            var settings = AppSettings()
            settings.usageThresholdMinutes = 90
            settings.overlayText = "Keep my preferences"
            var document = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            let defaultDocument = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
            document[key] = defaultDocument[key] ?? NSNull()
            let expected = try JSONDecoder().decode(
                AppSettings.self, from: JSONSerialization.data(withJSONObject: document))
            document[key] = [true]
            defaults.set(try JSONSerialization.data(withJSONObject: document), forKey: DefaultsKey.settings)
            #expect(AppSettings.load(from: defaults) == expected)
        }
    }

    @Test func malformedLegacyChannelDoesNotDiscardOtherChannelsOrSettings() throws {
        try withDefaults { defaults in
            defaults.set(
                Data(#"{"channels":{"keyboard":"bad","mouse":false,"screenChanges":true},"breakSeconds":120}"#.utf8),
                forKey: DefaultsKey.settings)
            let settings = AppSettings.load(from: defaults)
            #expect(settings.breakSeconds == 120)
            #expect(settings.countVideoPlayback)
            let document = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            let channels = try #require(document["channels"] as? [String: Bool])
            #expect(channels == ["keyboard": true, "mouse": false, "screenChanges": true])
        }
    }

    @Test(arguments: ["garbage", "", "[]", "null"])
    func unreadableSettingsAreBackedUpBeforeAnEdit(contents: String) throws {
        try withDefaults { defaults in
            let original = Data(contents.utf8)
            defaults.set(original, forKey: DefaultsKey.settings)
            var settings = AppSettings.load(from: defaults)
            #expect(settings == AppSettings())
            #expect(defaults.data(forKey: DefaultsKey.settings) == original)
            #expect(backups(in: defaults, for: DefaultsKey.settings) == [original])
            settings.overlayText = "An unrelated edit"
            defaults.set(try JSONEncoder().encode(settings), forKey: DefaultsKey.settings)
            #expect(backups(in: defaults, for: DefaultsKey.settings) == [original])
        }
    }

    @Test func unreadableCurrentSettingsArePreservedBeforeLegacyShortcutMigrationSaves() throws {
        try withDefaults { defaults in
            let original = Data([0xFF, 0x00, 0xFE])
            defaults.set(original, forKey: DefaultsKey.settings)
            defaults.set(Data(#"{"breakSeconds":180}"#.utf8), forKey: DefaultsKey.legacySettings)
            defaults.set(Data(#"{"keyCode":15,"modifiers":2304}"#.utf8), forKey: DefaultsKey.legacyRestHotkey)
            var expected = AppSettings()
            expected.breakSeconds = 180
            expected.restHotkey = HotKeyCombo(keyCode: 15, modifiers: 2304)
            var recoveries: [AppSettings.Recovery] = []
            let loaded = AppSettings.load(from: defaults, now: TestDates.date(day: 25)) { recovery in
                recoveries.append(recovery)
                #expect(defaults.data(forKey: DefaultsKey.settings) == original)
                #expect(defaults.data(forKey: recovery.backupKey) == original)
                #expect(recovery.sourceKey == DefaultsKey.settings)
                #expect(recovery.backupKey.hasPrefix("\(DefaultsKey.settings).corrupt-2026-10-25T"))
            }
            #expect(loaded == expected)
            #expect(recoveries.count == 1)
            #expect(backups(in: defaults, for: DefaultsKey.settings) == [original])
            #expect(defaults.object(forKey: DefaultsKey.legacyRestHotkey) == nil)
            #expect(AppSettings.load(from: defaults) == expected)
            #expect(backups(in: defaults, for: DefaultsKey.settings) == [original])
        }
    }

    @Test func unreadableLegacySettingsAndRepeatedRecoveriesKeepEveryOriginal() throws {
        try withDefaults { defaults in
            let legacy = Data("broken legacy".utf8)
            defaults.set(legacy, forKey: DefaultsKey.legacySettings)
            for contents in ["first broken settings", "second broken settings"] {
                defaults.set(Data(contents.utf8), forKey: DefaultsKey.settings)
                #expect(AppSettings.load(from: defaults, now: TestDates.date(day: 25)) == AppSettings())
            }
            #expect(
                Set(backups(in: defaults, for: DefaultsKey.settings))
                    == Set([
                        Data("first broken settings".utf8), Data("second broken settings".utf8),
                    ]))
            #expect(Set(backups(in: defaults, for: DefaultsKey.legacySettings)) == [legacy])
        }
    }
}
