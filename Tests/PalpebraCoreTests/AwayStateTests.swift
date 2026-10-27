import Foundation
import PalpebraCore
import Testing

struct AwayStateTests {
    @Test func overlappingSignalsEndOnlyAfterTheLastWakeAndAreConsumedOnce() {
        let start = TestDates.date(day: 25)
        var state = AwayState()
        state.set(.lock, active: true, at: start)
        state.set(.displaySleep, active: true, at: start.addingTimeInterval(5))
        state.set(.systemSleep, active: true, at: start.addingTimeInterval(10))
        state.set(.lock, active: true, at: start.addingTimeInterval(20))
        #expect(state.startedAt == start)
        state.set(.systemSleep, active: false, at: start.addingTimeInterval(100))
        state.set(.displaySleep, active: false, at: start.addingTimeInterval(110))
        #expect(state.isAway)
        #expect(state.takeCompletedIntervals().isEmpty)
        let end = start.addingTimeInterval(120)
        state.set(.lock, active: false, at: end)
        #expect(!state.isAway)
        #expect(state.startedAt == nil)
        #expect(state.takeCompletedIntervals() == [DateInterval(start: start, end: end)])
        state.set(.lock, active: false, at: end.addingTimeInterval(1))
        #expect(state.takeCompletedIntervals().isEmpty)
    }
}
