import Foundation
import PalpebraCore
import Testing

struct BreakComplianceTests {
    @Test func existingMixedOutcomesCountOnlyCompletedRest() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            try Data(
                """
                [
                    {"day":"2026-10-24","breakStarts":5,"breakFinishes":5,
                     "finishReasons":["completed","skippedFree","skippedChallenge","ignored","emergency"]},
                    {"day":"2026-10-25","breakStarts":5,"breakFinishes":2,
                     "finishReasons":["completed","futureReason"]}
                ]
                """.utf8
            ).write(to: file)
            let history = try UsageHistory(contentsOf: file, now: TestDates.date(day: 25), calendar: TestDates.calendar)
            #expect(history.compliance(last: 0, now: TestDates.date(day: 25), calendar: TestDates.calendar) == 0.2)
            #expect(history.compliance(last: 1, now: TestDates.date(day: 25), calendar: TestDates.calendar) == 0.2)
            let buckets = history.buckets(
                last: 0, by: .monthly, now: TestDates.date(day: 25), calendar: TestDates.calendar)
            let summary = BreakSummary(summaries: buckets.map(\.breakSummary))
            #expect(summary.started == 10)
            #expect(summary.completed == 2)
            #expect(summary.skipped == 2)
            #expect(summary.ignored == 1)
            #expect(summary.emergency == 1)
            #expect(summary.compliance == 0.2)
            #expect(
                history.csv().split(separator: "\n").dropFirst().map(String.init) == [
                    "2026-10-24,0.0,0,0.0,5,5,1,2,20", "2026-10-25,0.0,0,0.0,5,2,1,0,20",
                ])
        }
    }

    @Test func finishCountersWithoutCompletedReasonsNeverImplyCompliance() {
        var record = DayRecord(day: "2026-10-25")
        record.breakStarts = 5
        record.breakFinishes = 5
        let history = UsageHistory(days: [record])
        #expect(history.compliance(last: 0, now: TestDates.date(day: 25), calendar: TestDates.calendar) == 0)
        #expect(history.csv().hasSuffix("2026-10-25,0.0,0,0.0,5,5,0,0,0"))
        #expect(BreakSummary().compliance == 0)
    }
}
