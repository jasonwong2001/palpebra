import Foundation

/// Coalesces overlapping system signals into recorded wall-clock away intervals.
package struct AwayState: Sendable {
    package enum Signal: Sendable { case lock, displaySleep, systemSleep }

    package private(set) var locked = false
    package private(set) var displayAsleep = false
    package private(set) var systemAsleep = false
    package private(set) var startedAt: Date?
    private var completed: [DateInterval] = []

    package var isAway: Bool { locked || displayAsleep || systemAsleep }

    package init() {}

    package mutating func set(_ signal: Signal, active: Bool, at now: Date) {
        let wasAway = isAway
        switch signal {
        case .lock: locked = active
        case .displaySleep: displayAsleep = active
        case .systemSleep: systemAsleep = active
        }
        if !wasAway, isAway { startedAt = now }
        if wasAway, !isAway, let start = startedAt {
            if now > start { completed.append(DateInterval(start: start, end: now)) }
            startedAt = nil
        }
    }

    package mutating func takeCompletedIntervals() -> [DateInterval] {
        let intervals = completed
        completed.removeAll()
        return intervals
    }
}
