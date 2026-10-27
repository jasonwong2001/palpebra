import Foundation
import PalpebraCore
import Testing

struct DetectionMigrationTests {
    @Test func legacyMovieModeBecomesTheVideoPreferenceAndExplicitNewValuesWin() throws {
        for oldValue in [false, true] {
            let old = "{\"channels\":{\"keyboard\":false,\"mouse\":false,\"screenChanges\":\(oldValue)}}"
            let migrated = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
            #expect(migrated.countVideoPlayback == oldValue)
            let encoded = try JSONEncoder().encode(migrated)
            let document = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(document["countVideoPlayback"] as? Bool == oldValue)
            #expect(try JSONDecoder().decode(AppSettings.self, from: encoded) == migrated)
            for newValue in [false, true] {
                let both = old.dropLast() + ",\"countVideoPlayback\":\(newValue)}"
                #expect(
                    try JSONDecoder().decode(AppSettings.self, from: Data(both.utf8)).countVideoPlayback == newValue)
            }
        }
    }

    @Test func migratedVideoSettingSurvivesLoadingV1AndSavingV2() throws {
        let suite = "org.palpebra.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data(#"{"channels":{"keyboard":true,"mouse":false,"screenChanges":true},"detectMode":"dumb"}"#.utf8),
            forKey: "palpebra.settings.v1")
        let migrated = AppSettings.load(from: defaults)
        #expect(migrated.countVideoPlayback)
        #expect(migrated.detectMode.rawValue == "dumb")
        defaults.set(try JSONEncoder().encode(migrated), forKey: DefaultsKey.settings)
        #expect(AppSettings.load(from: defaults) == migrated)
    }

    @Test func legacyInputChannelSwitchesCannotDisableHardwareInput() throws {
        for keyboard in [false, true] {
            for mouse in [false, true] {
                let json = "{\"channels\":{\"keyboard\":\(keyboard),\"mouse\":\(mouse),\"screenChanges\":false}}"
                let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
                let start = TestDates.date(day: 25)
                var core = FatigueCore(now: start)
                let events = core.step(
                    now: start.addingTimeInterval(5), signals: .init(inputIdleSeconds: 0), settings: settings)
                #expect(core.isUsingNow)
                #expect(events == [.recordActive(seconds: 5, fatigue: 0)])
            }
        }
    }
}
