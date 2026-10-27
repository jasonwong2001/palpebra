import Foundation

/// Rest countdowns show whole seconds left: the full time for the whole first second, and zero only at the end.
package enum Countdown: Sendable {
    package static func secondsRemaining(until end: Date, at now: Date) -> Int {
        // A microsecond of slack absorbs date rounding at second boundaries without hiding a real fraction.
        DisplayNumber.nonnegativeInteger((end.timeIntervalSince(now) - 0.000_001).rounded(.up))
    }

    /// The origin for once-a-second updates that land exactly as each whole second before `end` passes.
    package static func scheduleStart(until end: Date, at now: Date) -> Date {
        end.addingTimeInterval(-Double(secondsRemaining(until: end, at: now)))
    }

    package static func text(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    package static func spoken(seconds: Int) -> String {
        let seconds = max(0, seconds)
        let minutes = seconds / 60
        guard minutes > 0 else { return counted(seconds, "second") }
        let rest = seconds % 60
        return rest == 0 ? counted(minutes, "minute") : "\(counted(minutes, "minute")), \(counted(rest, "second"))"
    }
}

/// The mini reminder's rest, sampled by the engine every few seconds. Rest removes fatigue at exactly one second
/// of remaining rest per second, so while you rest the card can count down between samples. Activity adds time
/// slowly, so the card holds until the next sample shows it.
package struct RestSample: Equatable, Sendable {
    package var remainingSeconds: Double
    package var sampledAt: Date
    package var isResting: Bool

    package init(remainingSeconds: Double, sampledAt: Date, isResting: Bool) {
        self.remainingSeconds = remainingSeconds
        self.sampledAt = sampledAt
        self.isResting = isResting
    }

    /// When the countdown reaches zero if you keep resting; nil while activity holds it.
    package var end: Date? { isResting ? sampledAt.addingTimeInterval(max(0, remainingSeconds)) : nil }

    package func secondsRemaining(at now: Date) -> Int {
        let held = sampledAt.addingTimeInterval(max(0, remainingSeconds))
        return Countdown.secondsRemaining(until: end ?? held, at: isResting ? max(now, sampledAt) : sampledAt)
    }
}
