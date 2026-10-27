import Foundation
import PalpebraCore
import Testing

struct BucketRegressionTests {
    private var mondayCalendar: Calendar {
        var calendar = TestDates.calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    @Test func fourteenDaysProduceTwoWeeklyBuckets() {
        let records = (12...25).map { day in
            var record = DayRecord(day: "2026-10-\(day)")
            record.activeSeconds = 60
            record.fatiguedSeconds = 30
            record.breakStarts = 1
            return record
        }
        let buckets = UsageHistory(days: records).buckets(
            last: 0, by: .weekly, now: TestDates.date(day: 25), calendar: mondayCalendar)
        #expect(buckets.map(\.label) == ["Week of Oct 12", "Week of Oct 19"])
        #expect(buckets.map(\.activeMinutes) == [7, 7])
        #expect(buckets.map(\.fatiguedMinutes) == [3.5, 3.5])
        #expect(buckets.map(\.breakStarts) == [7, 7])
    }

    @Test func weeklyBucketsUseTheInjectedWeekRules() {
        let history = UsageHistory(days: [DayRecord(day: "2026-10-18")])
        var sundayCalendar = mondayCalendar
        sundayCalendar.firstWeekday = 1
        sundayCalendar.minimumDaysInFirstWeek = 1
        #expect(
            history.buckets(last: 0, by: .weekly, now: TestDates.date(day: 25), calendar: mondayCalendar).map(\.label)
                == ["Week of Oct 12"])
        #expect(
            history.buckets(last: 0, by: .weekly, now: TestDates.date(day: 25), calendar: sundayCalendar).map(\.label)
                == ["Week of Oct 18"])
    }

    @Test func dailyBucketsStayChronologicalAcrossNewYear() {
        let history = UsageHistory(days: [
            DayRecord(day: "2026-01-02"), DayRecord(day: "2025-12-31"),
            DayRecord(day: "2026-01-01"), DayRecord(day: "2025-12-30"),
        ])
        let buckets = history.buckets(last: 0, by: .daily, now: TestDates.date(day: 25), calendar: mondayCalendar)
        #expect(
            buckets.map(\.label) == ["Tue, Dec 30, 2025", "Wed, Dec 31, 2025", "Thu, Jan 1, 2026", "Fri, Jan 2, 2026"])
        #expect(
            history.buckets(last: 0, by: .monthly, now: TestDates.date(day: 25), calendar: mondayCalendar).map(\.label)
                == ["Dec 2025", "Jan 2026"])
        #expect(
            history.buckets(last: 0, by: .weekly, now: TestDates.date(day: 25), calendar: mondayCalendar).map(\.label)
                == ["Week of Dec 29, 2025"])
    }

    @Test func theSameMonthAndDayInDifferentYearsNeverMerge() {
        var old = DayRecord(day: "2025-10-20")
        old.activeSeconds = 60
        var recent = DayRecord(day: "2026-10-20")
        recent.activeSeconds = 120
        let history = UsageHistory(days: [recent, old])
        let daily = history.buckets(last: 0, by: .daily, now: TestDates.date(day: 25), calendar: mondayCalendar)
        #expect(daily.map(\.label) == ["Mon, Oct 20, 2025", "Tue, Oct 20, 2026"])
        #expect(daily.map(\.activeMinutes) == [1, 2])
        #expect(Set(daily.map(\.id)).count == 2)
        let weekly = history.buckets(last: 0, by: .weekly, now: TestDates.date(day: 25), calendar: mondayCalendar)
        #expect(weekly.map(\.label) == ["Week of Oct 20, 2025", "Week of Oct 19, 2026"])
        #expect(weekly.map(\.activeMinutes) == [1, 2])
        #expect(Set(weekly.map(\.id)).count == 2)
    }
}
