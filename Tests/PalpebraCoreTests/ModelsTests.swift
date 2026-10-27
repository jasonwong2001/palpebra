import Foundation
import PalpebraCore
import Testing

struct ModelsTests {
    @Test func missingSettingsKeysUseDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded == AppSettings())

        let partial = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"breakSeconds":120,"detectMode":"dumb","futureKey":true}"#.utf8)
        )
        var expected = AppSettings()
        expected.breakSeconds = 120
        expected.detectMode = .dumb
        #expect(partial == expected)
    }

    @Test func settingsRoundTrip() throws {
        var settings = AppSettings()
        settings.usageThresholdMinutes = 60
        settings.breakSeconds = 120
        settings.reminderIntervalMinutes = 10
        settings.skipMode = .free
        settings.reminderStyle = .mini
        settings.preNotification = false
        settings.screenTimeReminderEnabled = true
        settings.screenTimePrimaryHours = 2
        settings.screenTimeSecondaryHours = 6
        settings.detectMode = .dumb
        settings.countVideoPlayback = true
        settings.idleGraceSeconds = 90
        settings.popupBackground = .custom
        settings.miniBackground = .dark
        settings.overlayText = "Look into the distance"
        settings.overlayOpacity = 0.8
        settings.breakEndSound = false
        settings.showDockIcon = false
        settings.statusShowsFatigue = false
        settings.statusShowsHours = true
        settings.statusShowsMinutes = false
        settings.statusShowsReminderCount = true
        settings.launchAtLogin = true
        settings.restHotkey = HotKeyCombo(keyCode: 15, modifiers: 2304)

        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(data, forKey: DefaultsKey.settings)
        #expect(AppSettings.load(from: defaults) == settings)
        #expect(defaults.data(forKey: DefaultsKey.settings) == data)
        #expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.contains(".corrupt-") })
    }

    @Test func settingsLoadCurrentThenLegacyThenDefaults() throws {
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppSettings.load(from: defaults) == AppSettings())

        var legacy = AppSettings()
        legacy.breakSeconds = 180
        defaults.set(try JSONEncoder().encode(legacy), forKey: "palpebra.settings.v1")
        #expect(AppSettings.load(from: defaults) == legacy)

        var current = AppSettings()
        current.usageThresholdMinutes = 90
        defaults.set(try JSONEncoder().encode(current), forKey: "palpebra.settings.v2")
        #expect(AppSettings.load(from: defaults) == current)
    }

    @Test func dayRecordDecodesMissingFields() throws {
        let record = try JSONDecoder().decode(DayRecord.self, from: Data(#"{"day":"2026-10-25"}"#.utf8))
        #expect(record == DayRecord(day: "2026-10-25"))

        let legacy = try JSONDecoder().decode(
            DayRecord.self,
            from: Data(#"{"day":"2026-10-24","activeSeconds":600,"fatiguePeak":30,"futureKey":true}"#.utf8)
        )
        var expected = DayRecord(day: "2026-10-24")
        expected.activeSeconds = 600
        expected.fatiguePeak = 30
        #expect(legacy == expected)
    }
}
