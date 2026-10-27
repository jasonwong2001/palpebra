import Foundation
import PalpebraCore
import Testing

struct UsageNumericValidationTests {
    @Test(arguments: [
        #""activeSeconds":1e308"#, #""fatiguedSeconds":1e308"#, #""fatiguePeak":1e308"#,
        #""activeSeconds":-1"#, #""fatiguedSeconds":-1"#, #""fatiguePeak":-1"#,
        #""activeSeconds":604800.1"#, #""fatiguedSeconds":604800.1"#, #""fatiguePeak":100.1"#,
        #""breakStarts":-1"#, #""breakFinishes":-1"#, #""reminderCount":-1"#,
        #""breakStarts":9223372036854775807"#, #""breakFinishes":9223372036854775807"#,
        #""reminderCount":9223372036854775807"#,
        #""breakStarts":1000001"#, #""breakFinishes":1000001"#, #""reminderCount":1000001"#,
    ])
    func invalidNumbersUseLossyRecoveryAndKeepValidNeighbors(field: String) throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            // Generous bounds allow DST, clock changes and migrated duplicate-day totals.
            let original = Data(
                """
                [
                    {"day":"2026-10-24","activeSeconds":604800,"fatiguedSeconds":604800,"fatiguePeak":100,
                     "breakStarts":1000000,"breakFinishes":1000000,"reminderCount":1000000},
                    {"day":"2026-10-23",\(field)},
                    {"day":"2026-10-25","activeSeconds":60,"finishReasons":["futureOutcome"]}
                ]
                """.utf8)
            try original.write(to: file)
            let history = try UsageHistory(contentsOf: file, now: TestDates.date(day: 25), calendar: TestDates.calendar)
            #expect(history.days.map(\.day) == ["2026-10-24", "2026-10-25"])
            #expect(history.days.map(\.activeSeconds) == [604800, 60])
            #expect(history.days.first?.breakStarts == 1_000_000)
            #expect(history.days.last?.finishReasons == ["futureOutcome"])
            let recovery = try #require(history.recovery)
            #expect(recovery.skippedRecords == 1)
            #expect(try Data(contentsOf: recovery.backupURL) == original)
            let reloaded = try UsageHistory(
                contentsOf: file, now: TestDates.date(day: 25), calendar: TestDates.calendar)
            #expect(reloaded.days == history.days)
            #expect(reloaded.recovery == nil)
        }
    }

    @Test(arguments: ["activeSeconds", "fatiguedSeconds", "fatiguePeak"])
    func nonFiniteDecodedNumbersAreRejected(field: String) {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for value in ["Infinity", "-Infinity", "NaN"] {
            let data = Data("{\"day\":\"2026-10-25\",\"\(field)\":\"\(value)\"}".utf8)
            #expect(throws: DecodingError.self) { try decoder.decode(DayRecord.self, from: data) }
        }
    }
}
