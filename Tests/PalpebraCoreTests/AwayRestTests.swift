import Foundation
import PalpebraCore
import Testing

struct AwayRestTests {
    private let origin = TestDates.date(day: 25)

    private func workedCore(minutes: Int = 40, now: inout Date) -> FatigueCore {
        var core = FatigueCore(now: now)
        for _ in 0..<(minutes * 12) {
            now = now.addingTimeInterval(5)
            _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: AppSettings())
        }
        return core
    }

    @Test(arguments: [3600.0, 8 * 3600.0, 30.0])
    func recordedAwayTimeDecaysOnceWithoutBookingScreenTime(seconds: Double) {
        var now = origin
        var core = workedCore(now: &now)
        let before = core.fatigue
        let start = now
        // Timers may run during lock/display sleep, but the recorded interval is applied on return.
        _ = core.step(
            now: start.addingTimeInterval(5),
            signals: .init(inputIdleSeconds: 0, locked: seconds != 8 * 3600, asleep: seconds == 8 * 3600),
            settings: AppSettings())
        now = start.addingTimeInterval(seconds)
        let events = core.step(
            now: now, signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: start, end: now)]),
            settings: AppSettings())
        #expect(abs(core.fatigue - max(0, before - seconds / 3)) < 0.000_001)
        #expect(
            !events.contains {
                if case .recordActive = $0 { return true }
                return false
            })
        #expect(
            !events.contains {
                if case .recordFatigued = $0 { return true }
                return false
            })
        // A repeated interval cannot subtract the same rest twice.
        let rested = core.fatigue
        _ = core.step(
            now: now.addingTimeInterval(5),
            signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: start, end: now)]),
            settings: AppSettings())
        #expect(core.fatigue > rested)
    }

    @Test func unexplainedGapRequiresFiniteIdleEvidenceCoveringTheWholeGap() {
        for idle in [0.0, 299, 300, Double.infinity] {
            var now = origin
            var core = workedCore(now: &now)
            let before = core.fatigue
            let events = core.step(
                now: now.addingTimeInterval(300), signals: .init(inputIdleSeconds: idle), settings: AppSettings())
            #expect(core.fatigue == (idle == 300 ? 0 : before), "Idle sample: \(idle)")
            #expect(events.isEmpty)
        }
    }

    @Test func recordedRestDoesNotAuthorizeTheUnexplainedPartOfALongGap() {
        var now = origin
        var core = workedCore(now: &now)
        let before = core.fatigue
        let events = core.step(
            now: now.addingTimeInterval(300),
            signals: .init(
                inputIdleSeconds: 0,
                awayIntervals: [DateInterval(start: now.addingTimeInterval(100), duration: 30)]),
            settings: AppSettings())
        #expect(abs(core.fatigue - (before - 10)) < 0.000_001)
        #expect(events.isEmpty)
    }

    @Test func overlappingAwayIntervalsNeverDoubleCountRest() {
        var now = origin
        var core = workedCore(now: &now)
        let before = core.fatigue
        _ = core.step(
            now: now.addingTimeInterval(300),
            signals: .init(
                inputIdleSeconds: 0,
                awayIntervals: [
                    DateInterval(start: now, duration: 30),
                    DateInterval(start: now.addingTimeInterval(10), duration: 30),
                ]), settings: AppSettings())
        #expect(abs(core.fatigue - (before - 40 / 3)) < 0.000_001)
    }

    @Test func fullScreenBreakCompletesWhileLockedAndOnlyFinishesOnce() {
        var now = origin
        var core = workedCore(now: &now)
        core.markBreakRunning(at: now, settings: AppSettings())
        let locked = core.step(
            now: now.addingTimeInterval(300), signals: .init(inputIdleSeconds: 0, locked: true),
            settings: AppSettings())
        #expect(locked == [.breakFinished(.completed)])
        #expect(core.fatigue == 0)
        #expect(!core.breakRunning)
        let wake = core.step(
            now: now.addingTimeInterval(3600),
            signals: .init(inputIdleSeconds: 0, awayIntervals: [DateInterval(start: now, duration: 3600)]),
            settings: AppSettings())
        #expect(wake.isEmpty)
        #expect(core.fatigue == 0)
    }

    @Test func alwaysOnAndVideoStillTreatRecordedAwayAsRest() {
        for mode in DetectMode.allCases {
            var now = origin
            var core = workedCore(now: &now)
            let before = core.fatigue
            var settings = AppSettings()
            settings.detectMode = mode
            settings.countVideoPlayback = true
            _ = core.step(
                now: now.addingTimeInterval(30),
                signals: .init(
                    inputIdleSeconds: 0, videoPlaying: true,
                    awayIntervals: [DateInterval(start: now, duration: 30)]), settings: settings)
            #expect(abs(core.fatigue - (before - 10)) < 0.000_001)
        }
    }
}
