import Foundation
import PalpebraCore
import Testing

struct UsageHistoryTests {
    private let calendar = TestDates.calendar
    private let today = TestDates.date(day: 25)

    @Test func recordsAggregateWithinADay() throws {
        var history = UsageHistory()
        history.recordActive(seconds: 90, fatigue: 30, on: today, calendar: calendar)
        history.recordActive(seconds: 60, fatigue: 20, on: today, calendar: calendar)
        history.recordFatigued(seconds: 15, on: today, calendar: calendar)
        history.recordBreakStart(on: today, calendar: calendar)
        history.recordBreakFinish(reason: .completed, on: today, calendar: calendar)
        history.recordReminder(on: today, calendar: calendar)

        try #require(history.days.count == 1)
        let record = try #require(history.days.first)
        #expect(record.day == "2026-10-25")
        #expect(record.activeSeconds == 150)
        #expect(record.fatiguePeak == 30)
        #expect(record.fatiguedSeconds == 15)
        #expect(record.breakStarts == 1)
        #expect(record.breakFinishes == 1)
        #expect(record.finishReasons == ["completed"])
        #expect(history.activeSeconds(on: today, calendar: calendar) == 150)
        #expect(history.reminderCount(on: today, calendar: calendar) == 1)
        #expect(history.activeSeconds(on: TestDates.date(day: 24), calendar: calendar) == 0)
    }

    @Test func lookupsFindEachDayAmongAYearOfRecords() throws {
        var history = UsageHistory()
        for offset in stride(from: 369, through: 0, by: -1) {
            let date = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
            history.recordActive(seconds: Double(offset + 1), fatigue: 10, on: date, calendar: calendar)
            for _ in 0..<(offset % 3) { history.recordReminder(on: date, calendar: calendar) }
        }
        let hundredDaysAgo = try #require(calendar.date(byAdding: .day, value: -100, to: today))
        #expect(history.days.count == 370)
        #expect(history.activeSeconds(on: today, calendar: calendar) == 1)
        #expect(history.activeSeconds(on: hundredDaysAgo, calendar: calendar) == 101)
        #expect(history.activeSeconds(on: TestDates.date(day: 26), calendar: calendar) == 0)
        #expect(history.reminderCount(on: hundredDaysAgo, calendar: calendar) == 1)
        #expect(history.reminderCount(on: TestDates.date(day: 26), calendar: calendar) == 0)
        history.recordActive(seconds: 4, fatigue: 10, on: today, calendar: calendar)
        #expect(history.days.count == 370)
        #expect(history.activeSeconds(on: today, calendar: calendar) == 5)
    }

    /// Duplicate keys can only come from an edited or legacy file; reads and writes use the first one.
    @Test func duplicateDaysResolveToTheFirstRecord() {
        var first = DayRecord(day: "2026-10-25")
        first.activeSeconds = 60
        first.reminderCount = 1
        var second = DayRecord(day: "2026-10-25")
        second.activeSeconds = 120
        second.reminderCount = 2
        second.screenTimeNotifiedPrimary = true
        var history = UsageHistory(days: [first, second])
        #expect(history.activeSeconds(on: today, calendar: calendar) == 60)
        #expect(history.reminderCount(on: today, calendar: calendar) == 1)
        #expect(!history.screenTimeNotified(primary: true, on: today, calendar: calendar))
        history.recordActive(seconds: 5, fatigue: 0, on: today, calendar: calendar)
        #expect(history.days.map(\.activeSeconds) == [65, 120])
    }

    @Test func screenTimeFlagsBelongToTheirDayAndThreshold() {
        var history = UsageHistory()
        history.setScreenTimeNotified(primary: true, on: today, calendar: calendar)
        #expect(history.screenTimeNotified(primary: true, on: today, calendar: calendar))
        #expect(!history.screenTimeNotified(primary: false, on: today, calendar: calendar))
        #expect(!history.screenTimeNotified(primary: true, on: TestDates.date(day: 26), calendar: calendar))
        history.setScreenTimeNotified(primary: false, on: today, calendar: calendar)
        #expect(history.screenTimeNotified(primary: false, on: today, calendar: calendar))
    }

    @Test func queriesUseInclusiveCalendarDayWindows() {
        let history = UsageHistory(days: [
            DayRecord(day: "2026-10-25"), DayRecord(day: "2026-10-18"), DayRecord(day: "2026-10-19"),
        ])
        #expect(
            history.records(last: 7, now: today, calendar: calendar).map(\.day) == [
                "2026-10-19", "2026-10-25",
            ])
        #expect(history.records(last: 1, now: today, calendar: calendar).map(\.day) == ["2026-10-25"])
        #expect(
            history.records(last: 0, now: today, calendar: calendar).map(\.day) == [
                "2026-10-18", "2026-10-19", "2026-10-25",
            ])
    }

    @Test func rollingWindowsExcludeRecordsAfterToday() {
        let history = UsageHistory(days: [
            DayRecord(day: "2026-10-19"), DayRecord(day: "2026-10-25"), DayRecord(day: "2026-10-26"),
        ])
        #expect(
            history.records(last: 7, now: today, calendar: calendar).map(\.day) == [
                "2026-10-19", "2026-10-25",
            ])
        #expect(history.records(last: 1, now: today, calendar: calendar).map(\.day) == ["2026-10-25"])
        // A clock or time-zone change can leave future records; All time still exposes them.
        #expect(history.records(last: 0, now: today, calendar: calendar).count == 3)
    }

    @Test func retentionKeepsTheCutoffDay() throws {
        let cutoff = try #require(calendar.date(byAdding: .day, value: -370, to: today))
        let expired = try #require(calendar.date(byAdding: .day, value: -371, to: today))
        var history = UsageHistory()
        for date in [today, cutoff, expired] {
            history.recordActive(seconds: 5, fatigue: 10, on: date, calendar: calendar)
        }
        history.prune(now: today, calendar: calendar)
        #expect(
            history.days.map(\.day) == [
                DayKey.string(from: today, calendar: calendar), DayKey.string(from: cutoff, calendar: calendar),
            ])
    }

    @Test func loadingPrunesExpiredRecordsOnDiskBeforeAnyNewUsage() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            let expired = try #require(calendar.date(byAdding: .day, value: -371, to: today))
            let original = UsageHistory(days: [DayRecord(day: DayKey.string(from: expired, calendar: calendar))])
            try original.save(to: file)
            let loaded = try UsageHistory(contentsOf: file, now: today, calendar: calendar)
            #expect(loaded.days.isEmpty)
            #expect(try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)).isEmpty)
        }
    }

    @Test func jsonRoundTripUsesAnInjectedTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("palpebra-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("usage.json")

        var history = UsageHistory()
        history.recordActive(seconds: 600, fatigue: 42, on: today, calendar: calendar)
        history.recordFatigued(seconds: 30, on: today, calendar: calendar)
        history.recordBreakStart(on: today, calendar: calendar)
        history.recordBreakFinish(reason: .completed, on: today, calendar: calendar)
        history.recordReminder(on: today, calendar: calendar)
        history.setScreenTimeNotified(primary: true, on: today, calendar: calendar)
        history.setScreenTimeNotified(primary: false, on: today, calendar: calendar)
        try history.save(to: file)

        let decoded = try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file))
        #expect(decoded == history.days)
        let loaded = try UsageHistory(contentsOf: file, now: today, calendar: calendar)
        #expect(loaded.days == history.days)
    }

    @Test func csvExportsBreakCountsWithoutTheDuplicateReminderColumn() {
        let header =
            "date,active_minutes,fatigue_peak_percent,fatigue_peak_minutes,break_starts,break_finishes,breaks_completed,breaks_skipped,compliance_percent"
        #expect(UsageHistory().csv() == header)
        var history = UsageHistory()
        history.recordActive(seconds: 90, fatigue: 42, on: today, calendar: calendar)
        history.recordFatigued(seconds: 30, on: today, calendar: calendar)
        history.recordBreakStart(on: today, calendar: calendar)
        history.recordBreakFinish(reason: .completed, on: today, calendar: calendar)
        history.recordReminder(on: today, calendar: calendar)
        history.recordActive(seconds: 60, fatigue: 20, on: TestDates.date(day: 24), calendar: calendar)
        #expect(history.csv() == header + "\n2026-10-24,1.0,20,0.0,0,0,0,0,0\n2026-10-25,1.5,42,0.5,1,1,1,0,100")
    }

    /// Days without use, such as those before Palpebra was installed, don't dilute the average.
    @Test func dailyAveragesCountOnlyDaysWithUseInTheWindow() {
        var monday = DayRecord(day: "2026-10-19")
        monday.activeSeconds = 3600
        monday.fatiguedSeconds = 600
        var saturday = DayRecord(day: "2026-10-24")
        saturday.activeSeconds = 7200
        saturday.fatiguedSeconds = 1200
        var flagsOnly = DayRecord(day: "2026-10-25")
        flagsOnly.screenTimeNotifiedPrimary = true
        var outside = DayRecord(day: "2026-10-18")
        outside.activeSeconds = 36000
        let history = UsageHistory(days: [outside, monday, saturday, flagsOnly])

        let week = history.dailyAverage(last: 7, now: today, calendar: calendar)
        #expect(week == DailyAverage(activeMinutes: 90, fatiguedMinutes: 15, days: 2))
        let allTime = history.dailyAverage(last: 0, now: today, calendar: calendar)
        #expect(allTime == DailyAverage(activeMinutes: 260, fatiguedMinutes: 10, days: 3))
        #expect(UsageHistory().dailyAverage(last: 7, now: today, calendar: calendar) == DailyAverage())
    }

    @Test func dailyAndMonthlyBucketsAggregateUsage() throws {
        var first = DayRecord(day: "2026-10-01")
        first.activeSeconds = 120
        first.fatiguedSeconds = 60
        first.breakStarts = 1
        first.breakFinishes = 1
        var second = DayRecord(day: "2026-10-02")
        second.activeSeconds = 180
        second.fatiguedSeconds = 30
        second.breakStarts = 2
        second.breakFinishes = 2
        var third = DayRecord(day: "2026-11-01")
        third.activeSeconds = 600
        let history = UsageHistory(days: [third, second, first])
        let daily = history.buckets(last: 0, by: .daily, now: today, calendar: calendar)
        #expect(daily.map(\.label) == ["Thu, Oct 1", "Fri, Oct 2", "Sun, Nov 1"])
        #expect(daily.map(\.activeMinutes) == [2, 3, 10])
        #expect(daily.map(\.fatiguedMinutes) == [1, 0.5, 0])

        let monthly = history.buckets(last: 0, by: .monthly, now: today, calendar: calendar)
        #expect(monthly.map(\.label) == ["Oct 2026", "Nov 2026"])
        #expect(monthly.map(\.activeMinutes) == [5, 10])
        let october = try #require(monthly.first)
        #expect(october.fatiguedMinutes == 1.5)
        #expect(october.breakStarts == 3)
        #expect(october.breakFinishes == 3)
    }
}
