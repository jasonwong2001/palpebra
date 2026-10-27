import Foundation
import PalpebraCore
import Testing

struct DayKeyTests {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func noon(_ key: String, in calendar: Calendar) throws -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return try #require(
            calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)))
    }

    /// Clocks in these zones jump from 23:59 to 01:00, so the day has no midnight.
    @Test(arguments: [
        ("America/Santiago", "2025-09-07"), ("America/Asuncion", "2024-10-06"), ("Asia/Beirut", "2025-03-30"),
    ])
    func daysWithoutAMidnightStillParseToTheirStart(zone: String, key: String) throws {
        let calendar = try calendar(zone)
        let start = calendar.startOfDay(for: try noon(key, in: calendar))
        #expect(DayKey.date(from: key, calendar: calendar) == start)
    }

    /// Clocks in Havana fall back from 01:00 to 00:00, so midnight happens twice; the day starts at the first.
    @Test func daysWithTwoMidnightsStartAtTheFirst() throws {
        let calendar = try calendar("America/Havana")
        let start = calendar.startOfDay(for: try noon("2025-11-02", in: calendar))
        #expect(DayKey.date(from: "2025-11-02", calendar: calendar) == start)
    }

    @Test func historyKeepsDaysWithoutAMidnight() throws {
        let santiago = try calendar("America/Santiago")
        let now = try noon("2025-09-10", in: santiago)
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            let records = ["2025-09-06", "2025-09-07", "2025-09-08"].map { day in
                var record = DayRecord(day: day)
                record.activeSeconds = 600
                return record
            }
            try JSONEncoder().encode(records).write(to: file)
            let history = try UsageHistory(contentsOf: file, now: now, calendar: santiago)
            #expect(history.unmigratedDayKeys.isEmpty)
            let buckets = history.buckets(last: 7, by: .daily, now: now, calendar: santiago)
            #expect(buckets.count == 3)
            #expect(buckets.map(\.activeMinutes) == [10, 10, 10])
        }
    }

    /// The parser must agree with the strict POSIX formatter it replaces wherever that formatter worked.
    @Test(arguments: ["UTC", "Europe/London", "America/Los_Angeles", "Australia/Lord_Howe", "Asia/Kolkata"])
    func parsingMatchesTheStrictFormatterOnOrdinaryDays(zone: String) throws {
        let calendar = try calendar(zone)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var day = try noon("2023-12-25", in: calendar)
        for _ in 0..<800 {
            let key = formatter.string(from: day)
            #expect(DayKey.date(from: key, calendar: calendar) == formatter.date(from: key), "Key: \(key)")
            #expect(
                DayKey.string(from: try #require(DayKey.date(from: key, calendar: calendar)), calendar: calendar) == key
            )
            day = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        }
    }

    @Test(arguments: [
        "2026-02-29", "2026-04-31", "2026-00-10", "2026-13-01", "2026-01-00", "2026-01-32", "0000-01-01",
        "0008-99-99", "2026/10/25", "2026-10-2a", " 2026-10-25", "2026-10-250", "",
    ])
    func impossibleOrMalformedKeysAreRejected(key: String) {
        #expect(DayKey.date(from: key, calendar: TestDates.calendar) == nil)
    }

    @Test func leapDaysParse() {
        #expect(
            DayKey.date(from: "2028-02-29", calendar: TestDates.calendar)
                == TestDates.date(year: 2028, month: 2, day: 29, hour: 0))
        #expect(DayKey.date(from: "2000-02-29", calendar: TestDates.calendar) != nil)
        #expect(DayKey.date(from: "2100-02-29", calendar: TestDates.calendar) == nil)
    }
}
