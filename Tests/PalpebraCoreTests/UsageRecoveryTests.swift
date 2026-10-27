import Foundation
import PalpebraCore
import Testing

struct UsageRecoveryTests {
    private let now = TestDates.date(day: 25)
    private let calendar = TestDates.calendar

    private func backups(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("usage.corrupt-") && $0.pathExtension == "json" }
    }

    @Test func malformedRecordsKeepTheirValidNeighborsAndTheOriginalBytes() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            let original = Data(
                """
                [
                    {"day":"2026-10-24","activeSeconds":60},
                    {"day":"2026-10-25","activeSeconds":"broken"},
                    {"activeSeconds":90}, null, [1,2],
                    {"day":"2026-10-25","activeSeconds":120}
                ]
                """.utf8)
            try original.write(to: file)
            var history = try UsageHistory(contentsOf: file, now: now, calendar: calendar)
            #expect(history.days.map(\.day) == ["2026-10-24", "2026-10-25"])
            #expect(history.days.map(\.activeSeconds) == [60, 120])
            history.recordActive(seconds: 5, fatigue: 0, on: now, calendar: calendar)
            try history.save(to: file)
            let backup = try #require(backups(in: directory).only)
            #expect(try Data(contentsOf: backup) == original)
            #expect(try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)) == history.days)
        }
    }

    @Test(arguments: ["not JSON", "", "{}", "[null,42]"])
    func unreadableHistoryIsQuarantinedBeforeNewRecordsAreSaved(contents: String) throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            let original = Data(contents.utf8)
            try original.write(to: file)
            var history = try UsageHistory(contentsOf: file, now: now, calendar: calendar)
            #expect(history.days.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            let backup = try #require(backups(in: directory).only)
            #expect(try Data(contentsOf: backup) == original)
            history.recordActive(seconds: 5, fatigue: 0, on: now, calendar: calendar)
            try history.save(to: file)
            #expect(try Data(contentsOf: backup) == original)
            #expect(try JSONDecoder().decode([DayRecord].self, from: Data(contentsOf: file)) == history.days)
        }
    }

    @Test func backupNamesNeverOverwriteAnEarlierRecovery() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            for contents in ["first broken file", "second broken file"] {
                try Data(contents.utf8).write(to: file)
                _ = try UsageHistory(contentsOf: file, now: now, calendar: calendar)
            }
            let saved = try backups(in: directory)
            #expect(saved.count == 2)
            #expect(
                try Set(saved.map { try String(contentsOf: $0, encoding: .utf8) }) == [
                    "first broken file", "second broken file",
                ])
        }
    }

    @Test func partiallyRecoveredHistorySurvivesAnImmediateRestart() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            try Data(#"[{"day":"2026-10-25","activeSeconds":120},null]"#.utf8).write(to: file)
            let recovered = try UsageHistory(contentsOf: file, now: now, calendar: calendar)
            let reloaded = try UsageHistory(contentsOf: file, now: now, calendar: calendar)
            #expect(reloaded.days == recovered.days)
            #expect(reloaded.days.first?.activeSeconds == 120)
        }
    }

    @Test func missingAndValidEmptyHistoryStartCleanly() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("usage.json")
            #expect(try UsageHistory(contentsOf: file, now: now, calendar: calendar).days.isEmpty)
            try Data("[]".utf8).write(to: file)
            #expect(try UsageHistory(contentsOf: file, now: now, calendar: calendar).days.isEmpty)
            #expect(try backups(in: directory).isEmpty)
            #expect(try String(contentsOf: file, encoding: .utf8) == "[]")
        }
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
