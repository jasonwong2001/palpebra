import Foundation

/// Persisted keys are always ASCII Gregorian dates in the caller's time zone.
/// A single locked formatter writes keys for callers using different calendars and time zones;
/// parsing uses calendar arithmetic instead.
package enum DayKey: Sendable {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    package static func string(from date: Date, calendar: Calendar) -> String {
        withFormatter(timeZone: calendar.timeZone) { $0.string(from: date) }
    }

    /// The start of the key's day. A strict formatter can't parse days whose midnight a DST change skips,
    /// and picks the second of two midnights; calendar arithmetic finds the real start in both cases.
    package static func date(from key: String, calendar: Calendar) -> Date? {
        let bytes = Array(key.utf8)
        guard bytes.count == 10,
            bytes.enumerated().allSatisfy({ index, byte in
                index == 4 || index == 7 ? byte == 45 : (48...57).contains(byte)
            })
        else { return nil }
        func number(_ digits: Range<Int>) -> Int { bytes[digits].reduce(0) { $0 * 10 + Int($1 - 48) } }
        let year = number(0..<4)
        let month = number(5..<7)
        let day = number(8..<10)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        // The round trip rejects impossible days, such as February 30, instead of rolling them over.
        guard let date = gregorian.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parsed = gregorian.dateComponents([.year, .month, .day], from: date)
        return parsed.year == year && parsed.month == month && parsed.day == day ? date : nil
    }

    /// Distinguishes plausible Gregorian keys from old Buddhist/Islamic/Japanese calendar years.
    static func isCanonical(_ key: String, now: Date, calendar: Calendar) -> Bool {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard let year = Int(key.prefix(4)), year >= 2000, year <= gregorian.component(.year, from: now) + 1 else {
            return false
        }
        return date(from: key, calendar: calendar) != nil
    }

    /// Recreates the current-locale formatter that wrote legacy records. Tests inject other writers.
    static func legacyFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func withFormatter<T>(timeZone: TimeZone, _ operation: (DateFormatter) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if formatter.timeZone != timeZone { formatter.timeZone = timeZone }
        return operation(formatter)
    }
}
