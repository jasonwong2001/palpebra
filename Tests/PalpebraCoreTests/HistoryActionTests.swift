import Foundation
import PalpebraCore
import Testing

struct HistoryActionTests {
    @Test func failedClearPreservesTheHistoryForRetry() throws {
        try withTemporaryDirectory { directory in
            var history = UsageHistory()
            history.recordActive(seconds: 600, fatigue: 40, on: TestDates.date(day: 25), calendar: TestDates.calendar)
            let before = history.days
            #expect(throws: (any Error).self) { try history.clear(savedTo: directory) }
            #expect(history.days == before)
        }
    }

    @Test func successfulClearAlsoPersistsTheEmptyHistory() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            var history = UsageHistory()
            history.recordActive(seconds: 600, fatigue: 40, on: TestDates.date(day: 25), calendar: TestDates.calendar)
            try history.save(to: file)
            try history.clear(savedTo: file)
            #expect(history.days.isEmpty)
            #expect(
                try UsageHistory(contentsOf: file, now: TestDates.date(day: 25), calendar: TestDates.calendar).days
                    .isEmpty)
        }
    }
}
