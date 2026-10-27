import Foundation
import PalpebraCore
import Testing

struct FatigueRegressionTests {
    private let origin = TestDates.date(day: 25)

    private func filledCore(now: inout Date, settings: AppSettings) -> FatigueCore {
        var core = FatigueCore(now: now)
        // The threshold can land one sample late because of floating-point addition.
        while !core.breakRunning {
            now = now.addingTimeInterval(5)
            _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        }
        return core
    }

    @Test func fatiguedDurationOnlyCountsComputerUse() {
        let settings = AppSettings()
        for state in ["idle", "locked", "asleep", "pausedIdle", "active"] {
            var now = origin
            var core = filledCore(now: &now, settings: settings)
            core.completeBreak(reason: .skippedFree, at: now)
            if state == "pausedIdle" { core.pause(until: now.addingTimeInterval(60)) }
            now = now.addingTimeInterval(5)
            let events = core.step(
                now: now,
                signals: .init(
                    inputIdleSeconds: state == "active" ? 0 : 61,
                    locked: state == "locked", asleep: state == "asleep"),
                settings: settings)
            #expect(events.contains(.recordFatigued(seconds: 5)) == (state == "active"), "State: \(state)")
        }
    }

    @Test func screenTimeRulesStillFireBetweenFatigueReminders() {
        var settings = AppSettings()
        settings.screenTimeReminderEnabled = true
        settings.screenTimePrimaryHours = 1
        settings.screenTimeSecondaryHours = 2
        var now = origin
        var core = filledCore(now: &now, settings: settings)
        core.completeBreak(reason: .skippedFree, at: now)

        for (hours, primary) in [(1, true), (2, false)] {
            now = now.addingTimeInterval(5)
            let events = core.step(
                now: now,
                signals: .init(
                    inputIdleSeconds: 0, activeSecondsToday: Double(hours * 3600 - 5),
                    notifiedPrimary: !primary),
                settings: settings)
            #expect(!events.contains(.thresholdReached))
            #expect(events.contains(.screenTimeReminder(primary: primary)))
        }
        now = now.addingTimeInterval(5)
        let delivered = core.step(
            now: now,
            signals: .init(
                inputIdleSeconds: 0, activeSecondsToday: 7200, notifiedPrimary: true, notifiedSecondary: true),
            settings: settings)
        #expect(!delivered.contains(.screenTimeReminder(primary: true)))
        #expect(!delivered.contains(.screenTimeReminder(primary: false)))

        // The adapter supplies a new day's flags, so the rule can fire again tomorrow.
        core.resetClock(now: now.addingTimeInterval(86_400))
        now = now.addingTimeInterval(86_405)
        let tomorrow = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, activeSecondsToday: 3595), settings: settings)
        #expect(tomorrow.contains(.screenTimeReminder(primary: true)))
    }

    @Test(arguments: [BreakFinishReason.skippedFree, .skippedChallenge])
    func reminderIntervalStartsWhenTheSessionEnds(reason: BreakFinishReason) {
        let settings = AppSettings()
        var now = origin
        var core = filledCore(now: &now, settings: settings)
        // Include the pre-alert and nearly all of a five-minute break.
        for _ in 0..<71 {
            now = now.addingTimeInterval(5)
            _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        }
        core.completeBreak(reason: reason, at: now)
        let end = now
        for _ in 0..<59 {
            now = now.addingTimeInterval(5)
            let events = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
            #expect(!events.contains(.thresholdReached), "Only \(now.timeIntervalSince(end)) seconds since ending")
        }
        now = now.addingTimeInterval(5)
        let due = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(due.contains(.thresholdReached))
        now = now.addingTimeInterval(5)
        #expect(
            !core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings).contains(.thresholdReached))
    }
}
