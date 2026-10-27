import Foundation

/// A running session captures its delivery style, rest duration, deadline and skip rule.
struct BreakSession: Sendable {
    let style: ReminderStyle
    let restSeconds: Int
    let deadline: Date
    let skipMode: SkipMode
    var notificationDelivered: Bool
    var escapePressedAt: Date?

    static let emergencyHoldSeconds: Double = 5

    var emergencyDeadline: Date? { escapePressedAt?.addingTimeInterval(Self.emergencyHoldSeconds) }

    init(at now: Date, settings: AppSettings) {
        style = settings.reminderStyle
        skipMode = settings.skipMode
        restSeconds = settings.breakSeconds
        notificationDelivered = style != .notification
        // A non-blocking reminder gets the planned rest window plus the re-remind interval.
        // This leaves room for idle grace; a person walking away at 100% can actually finish.
        let timeout = restSeconds + (style == .fullscreen ? 0 : settings.reminderIntervalMinutes * 60)
        deadline = now.addingTimeInterval(Double(timeout))
    }

    func outcome(at now: Date, fatigue: Double) -> BreakFinishReason? {
        if style == .fullscreen, now >= deadline { return .completed }
        if hasRested(at: now, fatigue: fatigue) { return .completed }
        if skipMode == .locked, let emergencyDeadline, now >= emergencyDeadline { return .emergency }
        if style == .fullscreen { return nil }
        return now >= deadline ? .ignored : nil
    }

    func hasRested(at now: Date, fatigue: Double) -> Bool {
        // Reaching zero exactly at the captured deadline counts as completed.
        style != .fullscreen && notificationDelivered && now <= deadline && fatigue <= 0.000_001
    }
}
