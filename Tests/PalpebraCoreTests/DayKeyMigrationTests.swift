import Foundation
import PalpebraCore
import Testing

struct DayKeyMigrationTests {
    private let now = TestDates.date(day: 25)
    private let calendar = TestDates.calendar

    private func legacyFormatter(_ locale: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        let identifier: Calendar.Identifier
        switch locale {
        case "th_TH": identifier = .buddhist
        case "ar_SA": identifier = .islamicUmmAlQura
        default: identifier = .japanese
        }
        formatter.calendar = Calendar(identifier: identifier)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func populatedRecord(day: String) -> DayRecord {
        var record = DayRecord(day: day)
        record.activeSeconds = 120
        record.fatiguePeak = 70
        record.fatiguedSeconds = 30
        record.breakStarts = 2
        record.breakFinishes = 1
        record.finishReasons = ["completed"]
        record.reminderCount = 3
        record.screenTimeNotifiedPrimary = true
        return record
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .islamicUmmAlQura, .japanese])
    func nonGregorianCalendarsStillWriteGregorianASCIIKeys(identifier: Calendar.Identifier) throws {
        try withTemporaryDirectory { directory in
            var nonGregorian = Calendar(identifier: identifier)
            nonGregorian.timeZone = try #require(TimeZone(secondsFromGMT: 14 * 3600))
            let date = TestDates.date(day: 25, hour: 23)
            var history = UsageHistory()
            history.recordActive(seconds: 5, fatigue: 0, on: date, calendar: nonGregorian)
            let file = directory.appendingPathComponent("usage.json")
            try history.save(to: file)
            #expect(history.days.map(\.day) == ["2026-10-26"])
            var gregorian = calendar
            gregorian.timeZone = nonGregorian.timeZone
            #expect(DayKey.date(from: "2026-10-26", calendar: nonGregorian) == gregorian.startOfDay(for: date))
            #expect(try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)).first?.day == "2026-10-26")
        }
    }

    @Test(arguments: ["th_TH", "ar_SA", "ja_JP"])
    func legacyKeysMigrateAndPersistAllFields(locale: String) throws {
        try withTemporaryDirectory { directory in
            let formatter = legacyFormatter(locale)
            let oldKey = formatter.string(from: now)
            #expect(oldKey != "2026-10-25")
            let file = directory.appendingPathComponent("usage.json")
            try JSONEncoder().encode([populatedRecord(day: oldKey)]).write(to: file)
            let history = try UsageHistory(
                contentsOf: file, now: now, calendar: calendar, legacyDayKeyFormatter: formatter)
            let expected = [populatedRecord(day: "2026-10-25")]
            #expect(history.days == expected)
            #expect(try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)) == expected)
            #expect(try UsageHistory(contentsOf: file, now: now, calendar: calendar).days == expected)
            #expect(history.activeSeconds(on: now, calendar: calendar) == 120)
        }
    }

    @Test(arguments: ["th_TH", "ar_SA", "ja_JP"])
    func migrationMergesCollisionsWithoutLosingOutcomesOrFlags(locale: String) throws {
        try withTemporaryDirectory { directory in
            let formatter = legacyFormatter(locale)
            let first = populatedRecord(day: "2026-10-25")
            var second = populatedRecord(day: formatter.string(from: now))
            second.fatiguePeak = 90
            second.finishReasons = ["skippedFree"]
            second.screenTimeNotifiedPrimary = false
            second.screenTimeNotifiedSecondary = true
            let file = directory.appendingPathComponent("usage.json")
            try JSONEncoder().encode([first, second]).write(to: file)
            var history = try UsageHistory(
                contentsOf: file, now: now, calendar: calendar, legacyDayKeyFormatter: formatter)
            try #require(history.days.count == 1)
            var expected = populatedRecord(day: "2026-10-25")
            expected.activeSeconds = 240
            expected.fatiguePeak = 90
            expected.fatiguedSeconds = 60
            expected.breakStarts = 4
            expected.breakFinishes = 2
            expected.finishReasons = ["completed", "skippedFree"]
            expected.reminderCount = 6
            expected.screenTimeNotifiedSecondary = true
            #expect(history.days == [expected])
            #expect(try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)) == [expected])
            history.recordActive(seconds: 5, fatigue: 0, on: now, calendar: calendar)
            #expect(history.days.count == 1)
            #expect(history.activeSeconds(on: now, calendar: calendar) == 245)
        }
    }

    @Test func canonicalKeysStayUntouchedEvenWithALegacyCalendar() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            let original = Data("[{\"day\":\"2026-10-25\"}, {\"day\":\"2027-01-01\"}]\n".utf8)
            try original.write(to: file)
            let history = try UsageHistory(
                contentsOf: file, now: now, calendar: calendar, legacyDayKeyFormatter: legacyFormatter("th_TH"))
            #expect(history.days.map(\.day) == ["2026-10-25", "2027-01-01"])
            #expect(try Data(contentsOf: file) == original)
            #expect(DayKey.date(from: "٢٠٢٦-١٠-٢٥", calendar: calendar) == nil)
            #expect(DayKey.date(from: "2026-2-03", calendar: calendar) == nil)
            #expect(DayKey.date(from: "2026-02-30", calendar: calendar) == nil)
        }
    }

    @Test func unparseableLegacyKeysArePreservedInsteadOfPruned() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            let formatter = legacyFormatter("th_TH")
            let records = [populatedRecord(day: "0008-99-99"), populatedRecord(day: formatter.string(from: now))]
            try JSONEncoder().encode(records).write(to: file)
            let history = try UsageHistory(
                contentsOf: file, now: now, calendar: calendar, legacyDayKeyFormatter: formatter)
            #expect(history.days.map(\.day).sorted() == ["0008-99-99", "2026-10-25"])
            #expect(history.days.reduce(0) { $0 + $1.activeSeconds } == 240)
            #expect(
                try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)).map(\.day).sorted()
                    == ["0008-99-99", "2026-10-25"])
        }
    }
}
