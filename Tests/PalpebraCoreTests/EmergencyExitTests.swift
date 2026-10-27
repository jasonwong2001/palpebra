import Foundation
import PalpebraCore
import Testing

struct EmergencyExitTests {
    private let origin = TestDates.date(day: 25)

    private func runningCore(now: inout Date, settings: AppSettings) -> FatigueCore {
        var core = FatigueCore(now: now)
        while !core.breakRunning {
            now = now.addingTimeInterval(5)
            _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        }
        #expect(core.canQuitFromMenu)  // A reserved/pre-alert session has not locked the popup yet.
        core.markBreakRunning(at: now, settings: settings)
        core.markNotificationDelivered()
        return core
    }

    @Test(arguments: [ReminderStyle.fullscreen, .mini])
    func continuousFiveSecondHoldEndsLockedRestAsEmergencyAndPreservesFatigue(style: ReminderStyle) throws {
        var settings = AppSettings()
        settings.reminderStyle = style
        settings.skipMode = .locked
        var now = origin
        var core = runningCore(now: &now, settings: settings)
        #expect(!core.canQuitFromMenu)
        core.setEscapePressed(true, at: now)
        let start = now
        // Key repeat must not restart the hold clock.
        core.setEscapePressed(true, at: start.addingTimeInterval(3))
        now = start.addingTimeInterval(4.999)
        let early = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(!early.contains(.breakFinished(.emergency)))
        #expect(core.breakRunning)
        now = start.addingTimeInterval(5)
        let finished = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(finished.contains(.breakFinished(.emergency)))
        #expect(!core.breakRunning)
        #expect(core.canQuitFromMenu)
        #expect(core.fatigue == 100)
        #expect(
            !core.step(now: now.addingTimeInterval(5), signals: .init(inputIdleSeconds: 0), settings: settings)
                .contains(.thresholdReached))

        var history = UsageHistory()
        history.recordBreakStart(on: now, calendar: TestDates.calendar)
        for event in finished {
            if case .breakFinished(let reason) = event {
                history.recordBreakFinish(reason: reason, on: now, calendar: TestDates.calendar)
            }
        }
        let summary = BreakSummary(records: history.days)
        #expect(summary.emergency == 1)
        #expect(summary.completed == 0)
        #expect(summary.compliance == 0)
        let data = try JSONEncoder().encode(history.days)
        #expect(try JSONDecoder().decode([DayRecord].self, from: data) == history.days)
        #expect(try JSONDecoder().decode(BreakFinishReason.self, from: Data(#""emergency""#.utf8)) == .emergency)
    }

    @Test func releasingEscapeOrLosingFocusCancelsTheHoldAndANewHoldStartsFresh() {
        var settings = AppSettings()
        settings.skipMode = .locked
        var now = origin
        var core = runningCore(now: &now, settings: settings)
        core.setEscapePressed(true, at: now)
        core.setEscapePressed(false, at: now.addingTimeInterval(4))
        now = now.addingTimeInterval(6)
        #expect(
            !core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
                .contains(.breakFinished(.emergency)))
        #expect(core.breakRunning)
        core.setEscapePressed(true, at: now)
        now = now.addingTimeInterval(4)
        #expect(
            !core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
                .contains(.breakFinished(.emergency)))
        now = now.addingTimeInterval(1)
        #expect(
            core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
                .contains(.breakFinished(.emergency)))
    }

    /// Cannot skip disables Quit only where its emergency exit exists: a popup with the hold-Esc escape. A
    /// notification break has no popup, can't be enforced and ends as ignored, so it never traps the app.
    @Test func quitMenuDecisionUsesTheRunningSessionAndCannotBeChangedThroughSettings() {
        for style in ReminderStyle.allCases {
            for skip in SkipMode.allCases {
                var settings = AppSettings()
                settings.reminderStyle = style
                settings.skipMode = skip
                var now = origin
                var core = runningCore(now: &now, settings: settings)
                let canQuit = skip != .locked || style == .notification
                #expect(core.canQuitFromMenu == canQuit)
                settings.skipMode = skip == .locked ? .free : .locked
                now = now.addingTimeInterval(5)
                _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
                #expect(core.canQuitFromMenu == canQuit)
                core.completeBreak(reason: .ignored, at: now)
                #expect(core.canQuitFromMenu)
            }
        }
    }

    @Test func escapeDoesNotSkipOtherModesAndACompletedSessionCannotLeakAHold() {
        for skip in [SkipMode.free, .challenge, .locked] {
            var settings = AppSettings()
            settings.skipMode = skip
            var now = origin
            var core = runningCore(now: &now, settings: settings)
            core.setEscapePressed(true, at: now)
            if skip == .locked {
                core.completeBreak(reason: .skippedFree, at: now)
                core.markBreakRunning(at: now, settings: settings)
            }
            now = now.addingTimeInterval(5)
            #expect(
                !core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
                    .contains(.breakFinished(.emergency)))
            #expect(core.breakRunning)
        }
    }

    @Test func lockInterruptsAnEscapeHold() {
        var settings = AppSettings()
        settings.skipMode = .locked
        var now = origin
        var core = runningCore(now: &now, settings: settings)
        core.setEscapePressed(true, at: now)
        now = now.addingTimeInterval(4)
        _ = core.step(now: now, signals: .init(inputIdleSeconds: 0, locked: true), settings: settings)
        now = now.addingTimeInterval(2)
        #expect(
            !core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
                .contains(.breakFinished(.emergency)))
        #expect(core.breakRunning)
    }
}
