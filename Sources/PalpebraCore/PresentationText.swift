import Foundation

package enum AppVersion: Sendable {
    package static func label(version: String?, build: String?) -> String {
        guard let version, !version.isEmpty else { return "Palpebra — development build" }
        if let build, !build.isEmpty { return "Palpebra \(version) (\(build))" }
        return "Palpebra \(version)"
    }
}

package enum ReminderCopy: Sendable {
    package static func startTitle(manual: Bool) -> String {
        manual ? "Break started" : "Time to rest your eyes"
    }

    // Always on counts every unlocked minute as use, so there only a locked or sleeping Mac rests.

    /// The mini reminder's instruction under its countdown.
    package static func restInstruction(detectMode: DetectMode) -> String {
        detectMode == .dumb ? "Lock your Mac until this reaches zero." : "Look away until this reaches zero."
    }

    package static func countdownHint(detectMode: DetectMode) -> String {
        detectMode == .dumb ? "Counts down while your Mac is locked." : "Counts down while you look away."
    }

    package static func notificationBody(detectMode: DetectMode) -> String {
        detectMode == .dumb
            ? "Lock your Mac for a few minutes to rest." : "Look away from the screen for a few minutes."
    }
}

/// One way of writing durations across Today, the menu bar and Analysis: "45 min", "1 h", "3 h 40 min".
package enum DurationText: Sendable {
    package static func minutes(_ minutes: Int) -> String {
        let minutes = max(0, minutes)
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min"
    }

    /// Measured time counts whole minutes, like a clock: 45.9 minutes is still 45 min.
    package static func minutes(_ minutes: Double) -> String {
        self.minutes(DisplayNumber.nonnegativeInteger(minutes))
    }

    /// For VoiceOver, which would read "h" and "min" letter by letter.
    package static func spoken(minutes: Int) -> String {
        let minutes = max(0, minutes)
        let hours = minutes / 60
        guard hours > 0 else { return counted(minutes, "minute") }
        let rest = minutes % 60
        return rest == 0 ? counted(hours, "hour") : "\(counted(hours, "hour")) \(counted(rest, "minute"))"
    }
}

/// "1 minute", "2 minutes": English plurals for spoken text.
func counted(_ value: Int, _ unit: String) -> String {
    "\(value) \(unit)\(value == 1 ? "" : "s")"
}

/// When the next break comes, from the engine's published state.
package enum NextBreak: Equatable, Sendable {
    case running
    case paused
    /// Fatigue is falling, so nothing counts down.
    case resting
    /// At 100% and waiting out the re-remind interval.
    case due
    case inMinutes(Int)

    package init(breakRunning: Bool, paused: Bool, minutesToFull: Int?) {
        if breakRunning {
            self = .running
        } else if paused {
            self = .paused
        } else if let minutes = minutesToFull {
            self = minutes <= 0 ? .due : .inMinutes(minutes)
        } else {
            self = .resting
        }
    }

    /// Today's compact stat.
    package var value: String {
        switch self {
        case .running: return "Now"
        case .paused: return "Paused"
        case .resting: return "—"
        case .due: return "Due"
        case .inMinutes(let minutes): return "~" + DurationText.minutes(minutes)
        }
    }

    package var spoken: String {
        switch self {
        case .resting: return "Not counting down while you rest"
        case .inMinutes(let minutes): return "About " + DurationText.spoken(minutes: minutes)
        case .running, .paused, .due: return value
        }
    }

    /// The menu bar's sentence. The app adds when a pause ends, which needs the user's time format.
    package var sentence: String {
        switch self {
        case .running: return "Break in progress"
        case .paused: return "Reminders paused"
        case .resting: return "Resting"
        case .due: return "Break due"
        case .inMinutes(let minutes): return "Next break in ~" + DurationText.minutes(minutes)
        }
    }
}
