import Foundation
import PalpebraCore
import Testing

struct SessionDeadlineTests {
    private func runningCore(style: ReminderStyle, now: inout Date, settings: inout AppSettings) -> FatigueCore {
        settings.reminderStyle = style
        settings.breakSeconds = 20
        settings.reminderIntervalMinutes = 1
        var core = FatigueCore(now: now)
        while !core.breakRunning {
            now = now.addingTimeInterval(5)
            _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        }
        core.markBreakRunning(at: now, settings: settings)
        core.markNotificationDelivered()
        return core
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func auditLateLockIsIgnoredEvenThoughLaterRestClearsFatigue(style: ReminderStyle) {
        var now = TestDates.date(day: 25)
        var settings = AppSettings()
        var core = runningCore(style: style, now: &now, settings: &settings)
        let start = now
        let lock = start.addingTimeInterval(75)
        _ = core.step(now: lock, signals: .init(inputIdleSeconds: 0), settings: settings)
        _ = core.step(now: lock, signals: .init(inputIdleSeconds: 0, locked: true), settings: settings)
        now = start.addingTimeInterval(135)
        let events = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: lock, end: now)]),
            settings: settings)
        #expect(events == [.breakFinished(.ignored)])
        #expect(!core.breakRunning)
        #expect(core.fatigue == 0)
        #expect(core.sessionDeadline == nil)
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func restJustBeforeOrExactlyAtDeadlineCompletesButLaterRestDoesNot(style: ReminderStyle) {
        for offset in [-0.001, 0, 0.001] {
            var now = TestDates.date(day: 25)
            var settings = AppSettings()
            var core = runningCore(style: style, now: &now, settings: &settings)
            let start = now
            let lock = start.addingTimeInterval(60 + offset)
            _ = core.step(now: lock, signals: .init(inputIdleSeconds: 0), settings: settings)
            _ = core.step(now: lock, signals: .init(inputIdleSeconds: 0, asleep: true), settings: settings)
            now = start.addingTimeInterval(135)
            let events = core.step(
                now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: lock, end: now)]),
                settings: settings)
            #expect(events == [.breakFinished(offset <= 0 ? .completed : .ignored)], "Boundary offset: \(offset)")
            #expect(core.fatigue == 0)
            #expect(!core.breakRunning)
        }
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func delayedIdleSampleIsSplitAtDeadlineAndLaterRestStillDecays(style: ReminderStyle) {
        var now = TestDates.date(day: 25)
        var settings = AppSettings()
        var core = runningCore(style: style, now: &now, settings: &settings)
        let start = now
        _ = core.step(now: start.addingTimeInterval(75), signals: .init(inputIdleSeconds: 0), settings: settings)
        let events = core.step(
            now: start.addingTimeInterval(95), signals: .init(inputIdleSeconds: 61), settings: settings)
        #expect(events == [.breakFinished(.ignored)])
        #expect(core.fatigue == 0)
        #expect(!core.breakRunning)
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func delayedTimeoutStartsCooldownAtDeadlineEvenAcrossDroppedGaps(style: ReminderStyle) {
        for idle in [0.0, Double.infinity] {
            var now = TestDates.date(day: 25)
            var settings = AppSettings()
            var core = runningCore(style: style, now: &now, settings: &settings)
            let start = now
            // The >120-second gap has no rest evidence and is deliberately not booked as work.
            let expired = core.step(
                now: start.addingTimeInterval(139), signals: .init(inputIdleSeconds: idle), settings: settings)
            #expect(expired == [.breakFinished(.ignored)])
            #expect(core.fatigue == 100)
            let early = core.step(
                now: start.addingTimeInterval(139.999), signals: .init(inputIdleSeconds: 0), settings: settings)
            #expect(!early.contains(.thresholdReached))
            let due = core.step(
                now: start.addingTimeInterval(140), signals: .init(inputIdleSeconds: 0), settings: settings)
            #expect(due.contains(.thresholdReached))
        }
    }
}
