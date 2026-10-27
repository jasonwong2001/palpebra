import Foundation

/// Actions produced by a fatigue step. Usage events carry the seconds to book and the sampled fatigue.
package enum FatigueEvent: Equatable, Sendable {
    case recordActive(seconds: Double, fatigue: Double)
    case recordFatigued(seconds: Double)
    case thresholdReached
    case screenTimeReminder(primary: Bool)
    case pauseExpired
    case breakFinished(BreakFinishReason)
}

/// The fatigue state machine, driven entirely by explicit time, settings and system signals.
/// Activity raises fatigue by 100 / usageThresholdMinutes per minute; idle time lowers it by
/// 100 / breakMinutes per minute. Recorded lock/sleep intervals count as rest, never as screen use.
package struct FatigueCore: Sendable {
    /// One sample of the system and the day's persisted screen-time reminder state.
    /// After applying reminder events, it supplies the updated daily notification flags on the next step.
    package struct Signals: Sendable {
        package var inputIdleSeconds: Double
        package var locked: Bool
        package var asleep: Bool
        package var videoPlaying: Bool
        package var activeSecondsToday: Double
        package var notifiedPrimary: Bool
        package var notifiedSecondary: Bool
        package var awayIntervals: [DateInterval]

        package init(
            inputIdleSeconds: Double, locked: Bool = false, asleep: Bool = false, videoPlaying: Bool = false,
            activeSecondsToday: Double = 0, notifiedPrimary: Bool = false, notifiedSecondary: Bool = false,
            awayIntervals: [DateInterval] = []
        ) {
            self.inputIdleSeconds = inputIdleSeconds
            self.locked = locked
            self.asleep = asleep
            self.videoPlaying = videoPlaying
            self.activeSecondsToday = activeSecondsToday
            self.notifiedPrimary = notifiedPrimary
            self.notifiedSecondary = notifiedSecondary
            self.awayIntervals = awayIntervals
        }
    }

    package private(set) var fatigue: Double = 0
    package private(set) var isUsingNow = false
    package private(set) var pausedUntil: Date?
    package private(set) var breakRunning = false
    /// Minutes until 100% at the current activity rate, or nil while resting below 100%.
    package private(set) var minutesToFull: Int?

    private var lastTick: Date
    private var lastSessionEndedAt: Date?
    private var session: BreakSession?
    private var pendingStyle: ReminderStyle?

    package var sessionDeadline: Date? { session?.deadline }
    /// Gates app/menu Quit commands only; OS logout, restart and shutdown remain unrestricted. Cannot skip blocks
    /// Quit only for popups, which offer the hold-Esc emergency exit; a notification break has neither.
    package var canQuitFromMenu: Bool { session.map { $0.skipMode != .locked || $0.style == .notification } ?? true }
    package var emergencyExitDeadline: Date? { session?.emergencyDeadline }

    package mutating func setEscapePressed(_ pressed: Bool, at now: Date) {
        guard session?.skipMode == .locked else { return }
        if !pressed {
            session?.escapePressedAt = nil
        } else if session?.escapePressedAt == nil {
            session?.escapePressedAt = now
        }
    }

    /// Creates a fresh engine with an explicit sampling-clock origin.
    package init(now: Date) {
        lastTick = now
    }

    /// Restarts sampling without changing fatigue, pauses or an ongoing break.
    package mutating func resetClock(now: Date) {
        lastTick = now
    }

    /// Reads pause state without mutating it or producing events.
    package func isPaused(at now: Date) -> Bool {
        pausedUntil.map { $0 > now } ?? false
    }

    /// Whether `Signals.videoPlaying` can change a step, so callers can skip the system query otherwise.
    /// Only Smart mode reads it, at the Mac, once input has been quiet for the idle grace.
    package static func needsVideoSignal(inputIdleSeconds: Double, away: Bool, settings: AppSettings) -> Bool {
        settings.detectMode == .smart && settings.countVideoPlayback && !away
            && !(inputIdleSeconds < settings.idleGraceSeconds)
    }

    /// Advances one sample and returns usage bookings and reminder actions in their original order.
    /// The caller performs I/O and notification delivery; this method never reads a clock or starts a timer.
    package mutating func step(now: Date, signals: Signals, settings: AppSettings) -> [FatigueEvent] {
        var events: [FatigueEvent] = []
        let paused = isPaused(at: now)
        if pausedUntil != nil, !paused {
            pausedUntil = nil
            events.append(.pauseExpired)
        }

        let suppressed = signals.locked || signals.asleep
        let using: Bool
        if settings.detectMode == .dumb {
            using = !suppressed
        } else {
            var active = signals.inputIdleSeconds < settings.idleGraceSeconds
            if settings.countVideoPlayback, signals.videoPlaying {
                active = !suppressed
            }
            using = !suppressed && active
        }
        isUsingNow = using

        // Sleep can suspend the sampling timer. Keep the last accounting timestamp until return,
        // when the observer supplies the complete, timestamped interval in one step.
        if suppressed {
            session?.escapePressedAt = nil
            // Non-blocking sessions await the recorded rest interval on unlock/wake.
            if session?.style == .fullscreen { finishSessionIfDue(at: now, events: &events) }
            return events
        }
        let dt = now.timeIntervalSince(lastTick)
        let previousTick = lastTick
        let away = Self.mergedAwayIntervals(in: signals.awayIntervals, from: previousTick, to: now)
        let awaySeconds = away.reduce(0) { $0 + $1.duration }
        lastTick = now
        guard dt > 0 else {
            finishSessionIfDue(at: now, events: &events)
            return events
        }

        let sampledSeconds = dt < 120 ? max(0, dt - awaySeconds) : 0
        // Missing input samples are represented as infinity and are not evidence of rest.
        let confirmedIdleGap =
            dt >= 120 && !using && signals.inputIdleSeconds.isFinite
            && signals.inputIdleSeconds >= dt
        let activeSeconds = using ? sampledSeconds : 0
        let risePerMinute = 100.0 / Double(settings.usageThresholdMinutes)
        let decayPerMinute = 100.0 / (Double(session?.restSeconds ?? settings.breakSeconds) / 60.0)
        let freezesForBreak = breakRunning && (session?.style ?? pendingStyle ?? .fullscreen) == .fullscreen
        let updatesFatigue = !freezesForBreak && !paused

        // Preserve ordering around lock/unlock. Work before rest must be paid back; work
        // after sufficient rest cannot invalidate an already-earned session completion.
        let nonBlockingDeadline = session.flatMap { $0.style == .fullscreen ? nil : $0.deadline }
        var slices: [(interval: DateInterval, resting: Bool)] = []
        func appendSlice(from start: Date, to end: Date, resting: Bool) {
            guard end > start else { return }
            if let deadline = nonBlockingDeadline, deadline > start, deadline < end {
                slices.append((DateInterval(start: start, end: deadline), resting))
                slices.append((DateInterval(start: deadline, end: end), resting))
            } else {
                slices.append((DateInterval(start: start, end: end), resting))
            }
        }
        func appendSample(until end: Date, from start: Date) {
            if dt < 120, using || signals.inputIdleSeconds.isFinite {
                appendSlice(from: start, to: end, resting: !using)
            } else if confirmedIdleGap {
                appendSlice(from: start, to: end, resting: true)
            }
        }
        var cursor = previousTick
        for interval in away {
            appendSample(until: interval.start, from: cursor)
            appendSlice(from: interval.start, to: interval.end, resting: true)
            cursor = interval.end
        }
        appendSample(until: now, from: cursor)
        if updatesFatigue { finishSessionIfRested(at: now, events: &events) }
        for slice in slices {
            if let deadline = nonBlockingDeadline, slice.interval.start >= deadline {
                finishSessionIfDue(at: deadline, events: &events)
            }
            let seconds = slice.interval.duration
            if slice.resting {
                if updatesFatigue {
                    fatigue = max(0, fatigue - decayPerMinute * seconds / 60)
                    finishSessionIfRested(at: slice.interval.end, events: &events)
                }
            } else {
                events.append(.recordActive(seconds: seconds, fatigue: fatigue))
                if fatigue >= 80 { events.append(.recordFatigued(seconds: seconds)) }
                if updatesFatigue {
                    fatigue = min(100, fatigue + risePerMinute * seconds / 60)
                }
            }
            // Completion at the deadline wins; later rest only reduces overall fatigue.
            if let deadline = nonBlockingDeadline, slice.interval.end >= deadline {
                finishSessionIfDue(at: deadline, events: &events)
            }
        }

        finishSessionIfDue(at: now, events: &events)

        if fatigue < 100 {
            let remaining = 100 - fatigue
            minutesToFull = using ? Int(ceil(remaining / risePerMinute)) : nil
        } else {
            minutesToFull = 0
        }

        let interval = Double(settings.reminderIntervalMinutes) * 60
        let reminderDue = lastSessionEndedAt.map { now.timeIntervalSince($0) >= interval } ?? true
        if fatigue >= 100, !breakRunning, !paused, !suppressed, reminderDue {
            breakRunning = true
            pendingStyle = settings.reminderStyle
            events.append(.thresholdReached)
        }

        if settings.screenTimeReminderEnabled {
            let hours = (signals.activeSecondsToday + activeSeconds) / 3600
            if !signals.notifiedPrimary, hours >= Double(settings.screenTimePrimaryHours) {
                events.append(.screenTimeReminder(primary: true))
            }
            if !signals.notifiedSecondary, hours >= Double(settings.screenTimeSecondaryHours) {
                events.append(.screenTimeReminder(primary: false))
            }
        }
        return events
    }

    /// Clips and unions recorded intervals so overlapping lock/display/system sleep never doubles rest.
    private static func mergedAwayIntervals(in intervals: [DateInterval], from start: Date, to end: Date)
        -> [DateInterval]
    {
        guard end > start else { return [] }
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let lower = max(start, interval.start)
            let upper = min(end, interval.end)
            return upper > lower ? DateInterval(start: lower, end: upper) : nil
        }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private mutating func finishSessionIfRested(at now: Date, events: inout [FatigueEvent]) {
        guard session?.hasRested(at: now, fatigue: fatigue) == true else { return }
        completeBreak(reason: .completed, at: now)
        events.append(.breakFinished(.completed))
    }

    private mutating func finishSessionIfDue(at now: Date, events: inout [FatigueEvent]) {
        guard let session else { return }
        let end = session.style == .fullscreen ? now : min(now, session.deadline)
        guard let outcome = session.outcome(at: end, fatigue: fatigue) else { return }
        completeBreak(reason: outcome, at: end)
        events.append(.breakFinished(outcome))
    }

    /// Applies the coordinator's session outcome. Only completed rest resets fatigue.
    package mutating func completeBreak(reason: BreakFinishReason, at now: Date) {
        breakRunning = false
        session = nil
        pendingStyle = nil
        lastTick = max(lastTick, now)
        switch reason {
        case .completed:
            fatigue = 0
            minutesToFull = nil
            lastSessionEndedAt = nil
        case .skippedFree, .skippedChallenge, .ignored, .emergency:
            lastSessionEndedAt = now
        }
    }

    /// Starts the delivered session, capturing the settings and explicit start time.
    package mutating func markBreakRunning(at now: Date, settings: AppSettings) {
        breakRunning = true
        session = BreakSession(at: now, settings: settings)
        pendingStyle = nil
    }

    package func remainingRestSeconds(settings: AppSettings) -> Double {
        fatigue / 100 * Double(session?.restSeconds ?? settings.breakSeconds)
    }

    package mutating func markNotificationDelivered() {
        guard session?.style == .notification else { return }
        session?.notificationDelivered = true
    }

    /// Pauses reminders until the supplied date, or cancels the pause with nil. Pausing releases a reminder that
    /// hasn't started, such as one waiting out its one-minute warning; it returns again after the pause if fatigue
    /// is still full. Returns whether one was released, so the caller can cancel its warning.
    @discardableResult
    package mutating func pause(until: Date?) -> Bool {
        pausedUntil = until
        guard until != nil, breakRunning, session == nil else { return false }
        breakRunning = false
        pendingStyle = nil
        return true
    }
}
