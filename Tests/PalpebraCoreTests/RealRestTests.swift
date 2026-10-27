import Foundation
import PalpebraCore
import Testing

struct RealRestTests {
    private let origin = TestDates.date(day: 25)

    private func fullCore(now: inout Date, settings: AppSettings) -> FatigueCore {
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
    func actualIdleCompletesTheSessionAndCountsAsCompleted(style: ReminderStyle) {
        var settings = AppSettings()
        settings.reminderStyle = style
        settings.usageThresholdMinutes = 5
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        var finishes: [FatigueEvent] = []
        for _ in 0..<(settings.breakSeconds / 5) {
            now = now.addingTimeInterval(5)
            finishes += core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: settings)
        }
        #expect(finishes == [.breakFinished(.completed)])
        #expect(core.fatigue == 0)
        #expect(!core.breakRunning)
        var history = UsageHistory()
        history.recordBreakStart(on: now, calendar: TestDates.calendar)
        for event in finishes {
            if case .breakFinished(let reason) = event {
                history.recordBreakFinish(reason: reason, on: now, calendar: TestDates.calendar)
            }
        }
        #expect(BreakSummary(records: history.days).compliance == 1)
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func continuedWorkIsIgnoredThenCooldownStartsAtTheActualEnd(style: ReminderStyle) {
        var settings = AppSettings()
        settings.reminderStyle = style
        settings.usageThresholdMinutes = 5
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        // Preserve B20: allow the planned rest window, then the re-remind interval.
        let deadline = now.addingTimeInterval(Double(settings.breakSeconds + settings.reminderIntervalMinutes * 60))
        while now < deadline.addingTimeInterval(-5) {
            now = now.addingTimeInterval(5)
            let events = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
            #expect(!events.contains(.breakFinished(.completed)))
            #expect(!events.contains(.breakFinished(.ignored)))
        }
        now = deadline
        let expired = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(expired.contains(.breakFinished(.ignored)))
        #expect(!expired.contains(.thresholdReached))
        #expect(!core.breakRunning)
        #expect(core.fatigue == 100)
        var history = UsageHistory()
        history.recordBreakStart(on: now, calendar: TestDates.calendar)
        history.recordBreakFinish(reason: .ignored, on: now, calendar: TestDates.calendar)
        let summary = BreakSummary(records: history.days)
        #expect(summary.ignored == 1)
        #expect(summary.completed == 0)
        #expect(summary.compliance == 0)
        for _ in 0..<59 {
            now = now.addingTimeInterval(5)
            let events = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
            #expect(!events.contains(.thresholdReached))
            #expect(!events.contains(.breakFinished(.ignored)))
        }
        let due = core.step(
            now: now.addingTimeInterval(5), signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(due.contains(.thresholdReached))
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func walkingAwayWithTheDefaultIdleGraceCanCompleteBeforeTheDeadline(style: ReminderStyle) {
        var settings = AppSettings()
        settings.reminderStyle = style
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        var finished = false
        for seconds in stride(from: 5, through: 360, by: 5) {
            now = now.addingTimeInterval(5)
            let events = core.step(now: now, signals: .init(inputIdleSeconds: Double(seconds)), settings: settings)
            #expect(!events.contains(.breakFinished(.ignored)))
            finished = finished || events.contains(.breakFinished(.completed))
        }
        #expect(finished)
        #expect(core.fatigue == 0)
    }

    @Test func fullScreenStillFreezesAndFinishesByElapsedTime() {
        var now = origin
        var core = fullCore(now: &now, settings: AppSettings())
        now = now.addingTimeInterval(30)
        _ = core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: AppSettings())
        #expect(core.fatigue == 100)
        #expect(core.breakRunning)
    }

    @Test func miniRemainingTimeFollowsFatigueAndStopsDecreasingDuringActivity() {
        var settings = AppSettings()
        settings.reminderStyle = .mini
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        #expect(core.remainingRestSeconds(settings: settings) == 300)
        now = now.addingTimeInterval(30)
        _ = core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: settings)
        #expect(abs(core.remainingRestSeconds(settings: settings) - 270) < 0.000_001)
        now = now.addingTimeInterval(30)
        _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(core.remainingRestSeconds(settings: settings) > 270)
        let beforeLock = core.remainingRestSeconds(settings: settings)
        let start = now
        now = now.addingTimeInterval(30)
        _ = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: start, end: now)]),
            settings: settings)
        #expect(abs(core.remainingRestSeconds(settings: settings) - (beforeLock - 30)) < 0.000_001)
    }

    @Test func notificationCannotCompleteBeforeDeliveryIsConfirmed() {
        var settings = AppSettings()
        settings.reminderStyle = .notification
        var now = origin
        var core = FatigueCore(now: now)
        core.markBreakRunning(at: now, settings: settings)
        now = now.addingTimeInterval(5)
        #expect(core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: settings).isEmpty)
        #expect(core.breakRunning)
        core.markNotificationDelivered()
        now = now.addingTimeInterval(5)
        #expect(
            core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: settings)
                == [.breakFinished(.completed)])
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func recordedSleepCompletesNonBlockingRestEvenAfterItsDeadline(style: ReminderStyle) {
        var settings = AppSettings()
        settings.reminderStyle = style
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        let start = now
        now = now.addingTimeInterval(8 * 3600)
        let events = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: start, end: now)]),
            settings: settings)
        #expect(events == [.breakFinished(.completed)])
        #expect(core.fatigue == 0)
    }

    @Test func changingBreakDurationDoesNotMakeTheMiniRestCounterLie() {
        var settings = AppSettings()
        settings.reminderStyle = .mini
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        settings.breakSeconds = 60
        now = now.addingTimeInterval(30)
        _ = core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: settings)
        #expect(abs(core.remainingRestSeconds(settings: settings) - 270) < 0.000_001)
    }

    @Test func shortRecordedRestAppliesAfterTheActivityBeforeLock() {
        var settings = AppSettings()
        settings.reminderStyle = .mini
        settings.breakSeconds = 20
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        let lock = now.addingTimeInterval(2)
        _ = core.step(now: lock, signals: .init(inputIdleSeconds: 0, locked: true), settings: settings)
        now = lock.addingTimeInterval(20)
        let events = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: lock, end: now)]),
            settings: settings)
        #expect(events.contains(.breakFinished(.completed)))
        #expect(core.fatigue == 0)
        #expect(events.contains(.recordActive(seconds: 2, fatigue: 100)))
    }

    @Test func restEarnedBeforeNewActivityStillCompletesAndKeepsTheNewFatigue() {
        var settings = AppSettings()
        settings.reminderStyle = .mini
        settings.breakSeconds = 20
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        let start = now
        now = now.addingTimeInterval(22)
        let events = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: start, duration: 20)]),
            settings: settings)
        #expect(events.contains(.breakFinished(.completed)))
        #expect(!core.breakRunning)
        #expect(abs(core.fatigue - 2 / 27) < 0.000_001)
        #expect(events.contains(.recordActive(seconds: 2, fatigue: 0)))
        #expect(!events.contains(.recordFatigued(seconds: 2)))
    }

    @Test func preLockActivityMustBePaidBackBeforePartialFatigueCanReachZero() {
        var settings = AppSettings()
        settings.reminderStyle = .mini
        settings.usageThresholdMinutes = 5
        settings.breakSeconds = 20
        var now = origin
        var core = FatigueCore(now: now)
        now = now.addingTimeInterval(60)
        _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(core.fatigue == 20)
        core.markBreakRunning(at: now, settings: settings)
        let start = now.addingTimeInterval(1)
        now = now.addingTimeInterval(5)
        let events = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: start, duration: 4)]),
            settings: settings)
        #expect(!events.contains(.breakFinished(.completed)))
        #expect(abs(core.fatigue - 1 / 3) < 0.000_001)
    }

    @Test(arguments: [ReminderStyle.mini, .notification])
    func missingInputSamplesCannotProveRealRest(style: ReminderStyle) {
        var settings = AppSettings()
        settings.reminderStyle = style
        var now = origin
        var core = fullCore(now: &now, settings: settings)
        now = now.addingTimeInterval(5)
        let events = core.step(now: now, signals: .init(inputIdleSeconds: .infinity), settings: settings)
        #expect(events.isEmpty)
        #expect(core.fatigue == 100)
        #expect(core.remainingRestSeconds(settings: settings) == 300)
    }
}
