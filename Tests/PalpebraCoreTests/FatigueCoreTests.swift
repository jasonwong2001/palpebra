import Foundation
import PalpebraCore
import Testing

struct FatigueCoreTests {
    private let origin = TestDates.date(day: 25)

    private func advance(
        _ core: inout FatigueCore, now: inout Date, seconds: Int, idle: Double,
        settings: AppSettings = AppSettings()
    ) -> [FatigueEvent] {
        var events: [FatigueEvent] = []
        for _ in stride(from: 0, to: seconds, by: 5) {
            now = now.addingTimeInterval(5)
            events += core.step(now: now, signals: .init(inputIdleSeconds: idle), settings: settings)
        }
        return events
    }

    @Test func activityReachesFullFatigueAndTriggersOneBreak() {
        let settings = AppSettings()
        var now = origin
        var core = FatigueCore(now: now)
        let events = advance(
            &core, now: &now, seconds: settings.usageThresholdMinutes * 60, idle: 0, settings: settings
        )
        #expect(abs(core.fatigue - 100) <= 0.5)
        #expect(events.filter { $0 == .thresholdReached }.count == 1)
        #expect(core.breakRunning)
        #expect(core.minutesToFull == 0)
        let later = advance(&core, now: &now, seconds: 60, idle: 0)
        #expect(!later.contains(.thresholdReached))
    }

    @Test func idleRestDecaysFromFullFatigueToZero() {
        let settings = AppSettings()
        var now = origin
        var core = FatigueCore(now: now)
        _ = advance(&core, now: &now, seconds: settings.usageThresholdMinutes * 60, idle: 0)
        core.completeBreak(reason: .skippedFree, at: now)
        #expect(abs(core.fatigue - 100) <= 0.5)
        _ = advance(&core, now: &now, seconds: settings.breakSeconds, idle: 61)
        #expect(abs(core.fatigue) <= 0.5)
        #expect(core.minutesToFull == nil)
    }

    @Test func idleGraceSeparatesActivityFromRest() {
        var core = FatigueCore(now: origin)
        let active = core.step(
            now: origin.addingTimeInterval(5), signals: .init(inputIdleSeconds: 59), settings: AppSettings()
        )
        #expect(core.isUsingNow)
        #expect(core.fatigue > 0)
        #expect(core.minutesToFull == 45)
        #expect(active == [.recordActive(seconds: 5, fatigue: 0)])
        let idle = core.step(
            now: origin.addingTimeInterval(10), signals: .init(inputIdleSeconds: 61), settings: AppSettings()
        )
        #expect(!core.isUsingNow)
        #expect(core.fatigue == 0)
        #expect(core.minutesToFull == nil)
        #expect(idle.isEmpty)
    }

    @Test func fatigueIsFrozenDuringPausesAndRunningBreaks() {
        var now = origin
        var core = FatigueCore(now: now)
        _ = advance(&core, now: &now, seconds: 600, idle: 0)
        let initial = core.fatigue
        core.pause(until: now.addingTimeInterval(3600))
        _ = advance(&core, now: &now, seconds: 30, idle: 0)
        #expect(core.isPaused(at: now))
        #expect(core.fatigue == initial)
        _ = advance(&core, now: &now, seconds: 30, idle: 61)
        #expect(core.fatigue == initial)

        core.pause(until: nil)
        core.markBreakRunning(at: now, settings: AppSettings())
        _ = advance(&core, now: &now, seconds: 30, idle: 0)
        #expect(core.breakRunning)
        #expect(core.fatigue == initial)
        _ = advance(&core, now: &now, seconds: 30, idle: 61)
        #expect(core.fatigue == initial)
    }

    @Test func alwaysOnModeUsesTheComputerUnlessLockedOrAsleep() {
        var settings = AppSettings()
        settings.detectMode = .dumb
        for (locked, asleep, expected) in [(false, false, true), (true, false, false), (false, true, false)] {
            var core = FatigueCore(now: origin)
            _ = core.step(
                now: origin.addingTimeInterval(5),
                signals: .init(inputIdleSeconds: .infinity, locked: locked, asleep: asleep),
                settings: settings
            )
            #expect(core.isUsingNow == expected)
            #expect((core.fatigue > 0) == expected)
        }
    }

    /// Pausing during the one-minute warning cancels the reminder: nothing may open while paused, and the
    /// reminder comes back once the pause ends if fatigue is still full.
    @Test func pausingReleasesAReminderThatHasNotStartedYet() {
        let settings = AppSettings()
        var now = origin
        var core = FatigueCore(now: now)
        _ = advance(&core, now: &now, seconds: settings.usageThresholdMinutes * 60, idle: 0)
        #expect(core.breakRunning)
        let released = core.pause(until: now.addingTimeInterval(1800))
        #expect(released)
        #expect(!core.breakRunning)
        #expect(!advance(&core, now: &now, seconds: 60, idle: 0).contains(.thresholdReached))
        now = now.addingTimeInterval(1800)
        let resumed = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(resumed.contains(.pauseExpired))
        #expect(resumed.contains(.thresholdReached))
    }

    /// A started session is the coordinator's to end; pausing or resuming doesn't release it.
    @Test func pausingKeepsASessionThatHasStarted() {
        var now = origin
        var core = FatigueCore(now: now)
        _ = advance(&core, now: &now, seconds: AppSettings().usageThresholdMinutes * 60, idle: 0)
        core.markBreakRunning(at: now, settings: AppSettings())
        let pausing = core.pause(until: now.addingTimeInterval(1800))
        #expect(!pausing)
        #expect(core.breakRunning)
        let resuming = core.pause(until: nil)
        #expect(!resuming)
        #expect(core.breakRunning)
    }

    @Test func expiredPauseReadsArePureAndTheNextStepClearsItOnce() {
        var core = FatigueCore(now: origin)
        let expiry = origin.addingTimeInterval(5)
        core.pause(until: expiry)
        #expect(core.isPaused(at: origin))

        for _ in 0..<3 {
            #expect(!core.isPaused(at: expiry))
            #expect(core.pausedUntil == expiry)
        }

        let events = core.step(now: expiry, signals: .init(inputIdleSeconds: 61), settings: AppSettings())
        #expect(events == [.pauseExpired])
        #expect(core.pausedUntil == nil)

        for offset in [5.0, 10.0, 15.0] {
            let now = expiry.addingTimeInterval(offset)
            #expect(!core.isPaused(at: now))
            #expect(core.pausedUntil == nil)
            #expect(core.step(now: now, signals: .init(inputIdleSeconds: 61), settings: AppSettings()).isEmpty)
        }
    }

    @Test func videoSignalCountsOnlyWhenItsSettingIsEnabled() {
        for enabled in [false, true] {
            var core = FatigueCore(now: origin)
            var settings = AppSettings()
            settings.countVideoPlayback = enabled
            _ = core.step(
                now: origin.addingTimeInterval(5),
                signals: .init(inputIdleSeconds: .infinity, videoPlaying: true),
                settings: settings
            )
            #expect(core.isUsingNow == enabled)
        }
    }

    /// The app skips the display-assertion query whenever the answer can't change the step.
    @Test func videoSignalIsOnlyNeededWhenItCanChangeTheStep() {
        var neededCount = 0
        for mode in DetectMode.allCases {
            for enabled in [false, true] {
                for idle in [0, 59.9, 60, 61, 600, .infinity] {
                    for (locked, asleep) in [(false, false), (true, false), (false, true)] {
                        var settings = AppSettings()
                        settings.detectMode = mode
                        settings.countVideoPlayback = enabled
                        let needed = FatigueCore.needsVideoSignal(
                            inputIdleSeconds: idle, away: locked || asleep, settings: settings)
                        var withVideo = FatigueCore(now: origin)
                        var withoutVideo = FatigueCore(now: origin)
                        var differs = false
                        for second in stride(from: 5, through: 30, by: 5) {
                            let now = origin.addingTimeInterval(Double(second))
                            func signals(_ video: Bool) -> FatigueCore.Signals {
                                .init(inputIdleSeconds: idle, locked: locked, asleep: asleep, videoPlaying: video)
                            }
                            let a = withVideo.step(now: now, signals: signals(true), settings: settings)
                            let b = withoutVideo.step(now: now, signals: signals(false), settings: settings)
                            differs =
                                differs || a != b || withVideo.fatigue != withoutVideo.fatigue
                                || withVideo.isUsingNow != withoutVideo.isUsingNow
                                || withVideo.minutesToFull != withoutVideo.minutesToFull
                        }
                        if !needed {
                            #expect(!differs, "mode \(mode) enabled \(enabled) idle \(idle) locked \(locked)")
                        }
                        if needed { neededCount += 1 }
                    }
                }
            }
        }
        // Smart mode with the option on, at the Mac, with input quiet for the grace or longer.
        #expect(neededCount == 4)
    }

    @Test func completedBreakResetsFatigueAndEndsTheSession() {
        var now = origin
        var core = FatigueCore(now: now)
        _ = advance(&core, now: &now, seconds: 600, idle: 0)
        core.markBreakRunning(at: now, settings: AppSettings())
        core.completeBreak(reason: .completed, at: now)
        #expect(core.fatigue == 0)
        #expect(!core.breakRunning)
    }

    @Test func screenTimeEventsUseTheDaysTotalsAndDeliveryFlags() {
        var core = FatigueCore(now: origin)
        var settings = AppSettings()
        settings.screenTimeReminderEnabled = true
        settings.screenTimePrimaryHours = 1
        settings.screenTimeSecondaryHours = 2
        let primary = core.step(
            now: origin.addingTimeInterval(5),
            signals: .init(inputIdleSeconds: 0, activeSecondsToday: 3595), settings: settings
        )
        #expect(primary.contains(.screenTimeReminder(primary: true)))
        #expect(!primary.contains(.screenTimeReminder(primary: false)))
        let secondary = core.step(
            now: origin.addingTimeInterval(10),
            signals: .init(inputIdleSeconds: 0, activeSecondsToday: 7195, notifiedPrimary: true), settings: settings
        )
        #expect(!secondary.contains(.screenTimeReminder(primary: true)))
        #expect(secondary.contains(.screenTimeReminder(primary: false)))
        let delivered = core.step(
            now: origin.addingTimeInterval(15),
            signals: .init(
                inputIdleSeconds: 0, activeSecondsToday: 7200, notifiedPrimary: true, notifiedSecondary: true),
            settings: settings
        )
        #expect(!delivered.contains(.screenTimeReminder(primary: true)))
        #expect(!delivered.contains(.screenTimeReminder(primary: false)))
    }
}
