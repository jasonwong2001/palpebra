import Foundation

/// Derived outcomes, never persisted: old history gets the corrected metric without rewriting counters.
package struct BreakSummary: Equatable, Sendable {
    package private(set) var started = 0
    package private(set) var completed = 0
    package private(set) var skipped = 0
    package private(set) var ignored = 0
    package private(set) var emergency = 0

    package var compliance: Double {
        started > 0 ? min(1, Double(completed) / Double(started)) : 0
    }

    package init(records: [DayRecord] = []) {
        for record in records { include(record) }
    }

    package init(summaries: [BreakSummary]) {
        for summary in summaries {
            started += summary.started
            completed += summary.completed
            skipped += summary.skipped
            ignored += summary.ignored
            emergency += summary.emergency
        }
    }

    mutating func include(_ record: DayRecord) {
        started += record.breakStarts
        for reason in record.finishReasons {
            switch reason {
            case BreakFinishReason.completed.rawValue: completed += 1
            case BreakFinishReason.skippedFree.rawValue, BreakFinishReason.skippedChallenge.rawValue: skipped += 1
            case BreakFinishReason.ignored.rawValue: ignored += 1
            case BreakFinishReason.emergency.rawValue: emergency += 1
            default: break
            }
        }
    }
}
