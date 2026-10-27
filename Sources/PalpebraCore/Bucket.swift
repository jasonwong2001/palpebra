import Foundation

/// Aggregation bucket for the selected granularity.
package struct Bucket: Identifiable, Sendable {
    package let startDate: Date
    package private(set) var label = ""
    package private(set) var activeMinutes: Double = 0
    package private(set) var fatiguedMinutes: Double = 0
    package private(set) var breakStarts = 0
    package private(set) var breakFinishes = 0
    package private(set) var breakSummary = BreakSummary()
    package var id: Date { startDate }

    private static let monthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func build(from records: [DayRecord], by granularity: AnalysisGranularity, calendar: Calendar) -> [Bucket] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var buckets: [Date: Bucket] = [:]
        var years = Set<Int>()
        for record in records {
            guard let date = DayKey.date(from: record.day, calendar: calendar) else { continue }
            let start: Date
            switch granularity {
            case .daily:
                start = calendar.startOfDay(for: date)
            case .weekly:
                start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            case .monthly:
                start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            }
            years.insert(gregorian.component(.year, from: date))
            var bucket = buckets[start] ?? Bucket(startDate: start)
            bucket.activeMinutes += record.activeSeconds / 60
            bucket.fatiguedMinutes += record.fatiguedSeconds / 60
            bucket.breakStarts += record.breakStarts
            bucket.breakFinishes += record.breakFinishes
            bucket.breakSummary.include(record)
            buckets[start] = bucket
        }
        // A week starting in December names its year when the range reaches into January.
        years.formUnion(buckets.keys.map { gregorian.component(.year, from: $0) })
        let spansYears = years.count > 1
        return buckets.values.sorted { $0.startDate < $1.startDate }.map { bucket in
            var labeled = bucket
            labeled.label = label(for: bucket.startDate, by: granularity, spansYears: spansYears, gregorian: gregorian)
            return labeled
        }
    }

    /// English Gregorian labels, "Mon, Oct 20", "Week of Oct 19" and "Oct 2026", formatted once per bucket.
    /// Days and weeks add their year when the range spans more than one.
    private static func label(
        for start: Date, by granularity: AnalysisGranularity, spansYears: Bool, gregorian: Calendar
    ) -> String {
        let parts = gregorian.dateComponents([.year, .month, .day, .weekday], from: start)
        let year = parts.year ?? 0
        let month = monthNames[(parts.month ?? 1) - 1]
        let day = "\(month) \(parts.day ?? 1)" + (spansYears ? ", \(year)" : "")
        switch granularity {
        case .daily:
            return "\(weekdayNames[(parts.weekday ?? 1) - 1]), \(day)"
        case .weekly:
            return "Week of \(day)"
        case .monthly:
            return "\(month) \(year)"
        }
    }
}
