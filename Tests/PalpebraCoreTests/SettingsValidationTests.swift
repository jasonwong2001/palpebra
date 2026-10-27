import Foundation
import PalpebraCore
import Testing

struct SettingsValidationTests {
    @Test func popupBrightnessStaysWithinPickerBoundsAndRetainsNonPresetValues() throws {
        for (value, expected) in [
            (-1.0, 0.25), (0, 0.25), (0.249, 0.25), (0.25, 0.25),
            (0.37, 0.37), (0.9, 0.9), (1, 1), (1.01, 1), (1e308, 1),
        ] {
            let data = Data("{\"overlayOpacity\":\(value),\"breakSeconds\":120}".utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            #expect(settings.overlayOpacity == expected, "Brightness: \(value)")
            #expect(settings.breakSeconds == 120)
            #expect(SettingLimits.overlayBrightnessPercent.contains(Int((expected * 100).rounded())))
            #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for value in ["Infinity", "-Infinity", "NaN"] {
            let data = Data("{\"overlayOpacity\":\"\(value)\"}".utf8)
            #expect(try decoder.decode(AppSettings.self, from: data).overlayOpacity == AppSettings().overlayOpacity)
        }
    }

    @Test func invalidNumbersAreClampedOnDecode() throws {
        let low = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                #"{"usageThresholdMinutes":0,"breakSeconds":-1,"reminderIntervalMinutes":0,"idleGraceSeconds":0,"screenTimePrimaryHours":-4,"screenTimeSecondaryHours":0}"#
                    .utf8))
        #expect(low.usageThresholdMinutes == 5)
        #expect(low.breakSeconds == 20)
        #expect(low.reminderIntervalMinutes == 1)
        #expect(low.idleGraceSeconds == 10)
        #expect(low.screenTimePrimaryHours == 1)
        #expect(low.screenTimeSecondaryHours == 2)

        let high = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                #"{"usageThresholdMinutes":999,"breakSeconds":9999,"reminderIntervalMinutes":999,"idleGraceSeconds":9999,"screenTimePrimaryHours":99,"screenTimeSecondaryHours":99}"#
                    .utf8))
        #expect(high.usageThresholdMinutes == 240)
        #expect(high.breakSeconds == 1800)
        #expect(high.reminderIntervalMinutes == 60)
        #expect(high.idleGraceSeconds == 600)
        // Reserve the final supported hour for a strictly later second reminder.
        #expect(high.screenTimePrimaryHours == 15)
        #expect(high.screenTimeSecondaryHours == 16)
    }

    @Test(arguments: [(8, 8, 9), (12, 4, 13), (16, 1, 16)])
    func secondScreenTimeReminderIsAlwaysLater(primary: Int, secondary: Int, expected: Int) throws {
        let data = Data("{\"screenTimePrimaryHours\":\(primary),\"screenTimeSecondaryHours\":\(secondary)}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.screenTimeSecondaryHours == expected)
        #expect(settings.screenTimeSecondaryHours > settings.screenTimePrimaryHours)
    }

    @Test func anyValueWithinItsRangeIsKeptAndRoundTrips() throws {
        let data = Data(
            #"{"usageThresholdMinutes":37,"breakSeconds":85,"reminderIntervalMinutes":7,"idleGraceSeconds":42.5,"screenTimePrimaryHours":3,"screenTimeSecondaryHours":7}"#
                .utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.usageThresholdMinutes == 37)
        #expect(settings.breakSeconds == 85)
        #expect(settings.idleGraceSeconds == 42.5)
        #expect(settings.reminderIntervalMinutes == 7)
        #expect(settings.screenTimePrimaryHours == 3)
        #expect(settings.screenTimeSecondaryHours == 7)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test func changingScreenTimePickersMaintainsTheirOrdering() {
        var settings = AppSettings()
        settings.setScreenTimePrimaryHours(8)
        #expect(settings.screenTimeSecondaryHours == 9)
        settings.setScreenTimeSecondaryHours(4)
        #expect(settings.screenTimePrimaryHours == 3)
        #expect(settings.screenTimeSecondaryHours == 4)
    }
}
