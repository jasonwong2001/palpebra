import Foundation

/// Use per day, averaged over the days in a window that have any recorded use.
package struct DailyAverage: Equatable, Sendable {
    package var activeMinutes: Double
    package var fatiguedMinutes: Double
    /// Days with recorded use; zero means there is nothing to average.
    package var days: Int

    package init(activeMinutes: Double = 0, fatiguedMinutes: Double = 0, days: Int = 0) {
        self.activeMinutes = activeMinutes
        self.fatiguedMinutes = fatiguedMinutes
        self.days = days
    }
}
