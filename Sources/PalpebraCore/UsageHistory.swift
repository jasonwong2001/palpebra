import Foundation

/// Aggregated usage records without observation or a global storage location.
/// Dates, calendars and file URLs come from the caller; no operation reads the system clock.
package struct UsageHistory: Sendable {
    package private(set) var days: [DayRecord]

    /// A byte-for-byte backup made before recovering a damaged file.
    package struct Recovery: Sendable {
        package let backupURL: URL
        /// Nil means the entire document failed to decode.
        package let skippedRecords: Int?
    }

    package private(set) var recovery: Recovery?
    /// Legacy keys that the supplied writer could not interpret are retained for later recovery.
    package private(set) var unmigratedDayKeys: [String] = []

    /// Starts with an explicit set of records, or an empty history.
    package init(days: [DayRecord] = []) {
        self.days = days
    }

    /// Recovers valid records, preserving any damaged input before allowing a new save.
    /// Read or backup errors propagate so the adapter can disable saving for this session.
    package init(contentsOf fileURL: URL, now: Date, calendar: Calendar, legacyDayKeyFormatter: DateFormatter? = nil)
        throws
    {
        days = []
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }

        let decoded = try? JSONDecoder().decode(LossyRecords.self, from: data)
        days = decoded?.days ?? []
        if (decoded?.skippedRecords ?? 1) > 0 {
            let backup = try Self.quarantine(fileURL, now: now)
            recovery = Recovery(backupURL: backup, skippedRecords: decoded?.skippedRecords)
        }
        let migrated = migrateDayKeys(
            now: now, calendar: calendar,
            legacyFormatter: legacyDayKeyFormatter ?? DayKey.legacyFormatter(calendar: calendar))
        let countBeforePruning = days.count
        prune(now: now, calendar: calendar)
        if migrated || days.count != countBeforePruning || (recovery != nil && !days.isEmpty) {
            // Persist migration, retention and recovery before a restart or the next usage sample.
            try save(to: fileURL)
        }
    }

    private mutating func migrateDayKeys(now: Date, calendar: Calendar, legacyFormatter: DateFormatter) -> Bool {
        var changed = false
        let rekeyed = days.map { record in
            guard !DayKey.isCanonical(record.day, now: now, calendar: calendar) else { return record }
            if let date = legacyFormatter.date(from: record.day), legacyFormatter.string(from: date) == record.day {
                let key = DayKey.string(from: date, calendar: calendar)
                if DayKey.isCanonical(key, now: now, calendar: calendar) {
                    changed = true
                    return record.rekeyed(to: key)
                }
            }
            unmigratedDayKeys.append(record.day)
            return record
        }
        guard changed else { return false }
        var merged: [String: DayRecord] = [:]
        for record in rekeyed {
            if var previous = merged[record.day] {
                previous.mergeUsage(from: record)
                merged[record.day] = previous
            } else {
                merged[record.day] = record
            }
        }
        days = merged.values.sorted { $0.day < $1.day }
        return true
    }

    private struct LossyRecords: Decodable, Sendable {
        var days: [DayRecord] = []
        var skippedRecords = 0

        init(from decoder: Decoder) throws {
            var records = try decoder.unkeyedContainer()
            while !records.isAtEnd {
                // superDecoder advances past the whole element even if its record is malformed.
                let element = try records.superDecoder()
                do {
                    days.append(try DayRecord(from: element))
                } catch {
                    skippedRecords += 1
                }
            }
        }
    }

    private static func quarantine(_ fileURL: URL, now: Date) throws -> URL {
        let directory = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let timestamp = Int64(now.timeIntervalSince1970 * 1000)
        var suffix = 0
        var backup: URL
        repeat {
            let disambiguator = suffix == 0 ? "" : "-\(suffix)"
            backup = directory.appendingPathComponent("\(stem).corrupt-\(timestamp)\(disambiguator).json")
            suffix += 1
        } while FileManager.default.fileExists(atPath: backup.path)
        try FileManager.default.moveItem(at: fileURL, to: backup)
        return backup
    }

    /// Saves the existing JSON schema atomically to an explicitly supplied file.
    package func save(to fileURL: URL) throws {
        let data = try JSONEncoder().encode(days)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Clears the history on disk as well as in memory, reporting a failed write to the caller.
    package mutating func clear(savedTo fileURL: URL) throws {
        let empty = UsageHistory()
        try empty.save(to: fileURL)
        self = empty
    }

    private mutating func record(on date: Date, calendar: Calendar, mutate: (inout DayRecord) -> Void) {
        let key = DayKey.string(from: date, calendar: calendar)
        let index =
            days.firstIndex { $0.day == key }
            ?? {
                days.append(DayRecord(day: key))
                return days.count - 1
            }()
        mutate(&days[index])
    }

    /// Books active time and the fatigue sampled at the start of that interval.
    package mutating func recordActive(seconds: Double, fatigue: Double, on date: Date, calendar: Calendar) {
        record(on: date, calendar: calendar) { day in
            day.activeSeconds += seconds
            day.fatiguePeak = max(day.fatiguePeak, fatigue)
        }
    }

    /// Books an interval spent at or above the fatigue-peak threshold.
    package mutating func recordFatigued(seconds: Double, on date: Date, calendar: Calendar) {
        record(on: date, calendar: calendar) { $0.fatiguedSeconds += seconds }
    }

    /// Adds a break start to the selected day.
    package mutating func recordBreakStart(on date: Date, calendar: Calendar) {
        record(on: date, calendar: calendar) { $0.breakStarts += 1 }
    }

    /// Appends a session's persisted outcome and increments the existing finish counter.
    package mutating func recordBreakFinish(reason: BreakFinishReason, on date: Date, calendar: Calendar) {
        record(on: date, calendar: calendar) {
            $0.breakFinishes += 1
            $0.finishReasons.append(reason.rawValue)
        }
    }

    /// Adds a delivered break reminder to the selected day.
    package mutating func recordReminder(on date: Date, calendar: Calendar) {
        record(on: date, calendar: calendar) { $0.reminderCount += 1 }
    }

    /// The selected day's record. The key is formatted once, not once per record compared.
    private func existingRecord(on date: Date, calendar: Calendar) -> DayRecord? {
        let key = DayKey.string(from: date, calendar: calendar)
        return days.first { $0.day == key }
    }

    /// Whether the day's primary or secondary screen-time reminder has been delivered.
    package func screenTimeNotified(primary: Bool, on date: Date, calendar: Calendar) -> Bool {
        let day = existingRecord(on: date, calendar: calendar)
        return primary
            ? (day?.screenTimeNotifiedPrimary ?? false)
            : (day?.screenTimeNotifiedSecondary ?? false)
    }

    /// Marks one screen-time threshold as delivered for the selected day.
    package mutating func setScreenTimeNotified(primary: Bool, on date: Date, calendar: Calendar) {
        record(on: date, calendar: calendar) {
            if primary { $0.screenTimeNotifiedPrimary = true } else { $0.screenTimeNotifiedSecondary = true }
        }
    }

    /// The selected day's accumulated active time, or zero if it has no record.
    package func activeSeconds(on date: Date, calendar: Calendar) -> Double {
        existingRecord(on: date, calendar: calendar)?.activeSeconds ?? 0
    }

    /// The selected day's break-reminder count, or zero if it has no record.
    package func reminderCount(on date: Date, calendar: Calendar) -> Int {
        existingRecord(on: date, calendar: calendar)?.reminderCount ?? 0
    }

    /// Sorted records for a calendar-day window ending today; nonpositive windows include all records.
    package func records(last daysBack: Int, now: Date, calendar: Calendar) -> [DayRecord] {
        if daysBack <= 0 { return days.sorted { $0.day < $1.day } }
        let today = calendar.startOfDay(for: now)
        let cutoff =
            calendar.date(byAdding: .day, value: -(daysBack - 1), to: today)
            .map { DayKey.string(from: $0, calendar: calendar) } ?? ""
        let end = DayKey.string(from: today, calendar: calendar)
        return days.filter { $0.day >= cutoff && $0.day <= end }.sorted { $0.day < $1.day }
    }

    /// Completed rest divided by started breaks, derived from the persisted outcomes.
    package func compliance(last daysBack: Int, now: Date, calendar: Calendar) -> Double {
        BreakSummary(records: records(last: daysBack, now: now, calendar: calendar)).compliance
    }

    /// Days without use, such as those before the app was installed, don't dilute the average.
    package func dailyAverage(last daysBack: Int, now: Date, calendar: Calendar) -> DailyAverage {
        let used = records(last: daysBack, now: now, calendar: calendar).filter { $0.activeSeconds > 0 }
        guard !used.isEmpty else { return DailyAverage() }
        let days = Double(used.count)
        return DailyAverage(
            activeMinutes: used.reduce(0) { $0 + $1.activeSeconds } / 60 / days,
            fatiguedMinutes: used.reduce(0) { $0 + $1.fatiguedSeconds } / 60 / days,
            days: used.count)
    }

    /// Aggregates records with the selected calendar grouping.
    package func buckets(last daysBack: Int, by granularity: AnalysisGranularity, now: Date, calendar: Calendar)
        -> [Bucket]
    {
        Bucket.build(from: records(last: daysBack, now: now, calendar: calendar), by: granularity, calendar: calendar)
    }

    /// CSV of all history, including derived completed/skipped counts and corrected compliance.
    package func csv() -> String {
        var rows = [
            "date,active_minutes,fatigue_peak_percent,fatigue_peak_minutes,break_starts,break_finishes,breaks_completed,breaks_skipped,compliance_percent"
        ]
        for d in days.sorted(by: { $0.day < $1.day }) {
            let summary = BreakSummary(records: [d])
            rows.append(
                String(
                    format: "%@,%.1f,%.0f,%.1f,%d,%d,%d,%d,%d",
                    d.day, d.activeSeconds / 60, d.fatiguePeak, d.fatiguedSeconds / 60,
                    d.breakStarts, d.breakFinishes, summary.completed, summary.skipped,
                    Int(summary.compliance * 100)
                ))
        }
        return rows.joined(separator: "\n")
    }

    /// Drops records older than the existing 370-day retention window.
    package mutating func prune(now: Date, calendar: Calendar) {
        let cutoff =
            calendar.date(byAdding: .day, value: -370, to: now)
            .map { DayKey.string(from: $0, calendar: calendar) } ?? ""
        days.removeAll { DayKey.isCanonical($0.day, now: now, calendar: calendar) && $0.day < cutoff }
    }
}
