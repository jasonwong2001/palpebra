import Foundation
import PalpebraCore
import Testing

struct CountdownTests {
    private let start = TestDates.date(day: 25)

    @Test(arguments: [
        (0.0, 120), (0.003, 120), (0.5, 120), (0.999, 120), (1, 119), (59.5, 61), (119.5, 1), (120, 0), (130, 0),
    ])
    func countdownsShowTheFullTimeFirstAndZeroOnlyAtTheEnd(elapsed: Double, shown: Int) {
        let end = start.addingTimeInterval(120)
        #expect(Countdown.secondsRemaining(until: end, at: start.addingTimeInterval(elapsed)) == shown)
    }

    @Test func wholeSecondBoundariesSurviveDateArithmetic() {
        let end = start.addingTimeInterval(300)
        for seconds in 0...300 {
            let now = end.addingTimeInterval(-Double(seconds))
            #expect(Countdown.secondsRemaining(until: end, at: now) == seconds)
        }
    }

    @Test func updatesLandOnTheWholeSecondsBeforeTheEnd() {
        let end = start.addingTimeInterval(120)
        #expect(Countdown.scheduleStart(until: end, at: start.addingTimeInterval(0.003)) == start)
        #expect(Countdown.scheduleStart(until: end, at: start.addingTimeInterval(50.4)) == start.addingTimeInterval(50))
        #expect(Countdown.scheduleStart(until: end, at: end.addingTimeInterval(5)) == end)
    }

    @Test(arguments: [(120, "2:00"), (119, "1:59"), (59, "0:59"), (0, "0:00"), (3600, "60:00")])
    func clockTextUsesMinutesAndTwoDigitSeconds(seconds: Int, text: String) {
        #expect(Countdown.text(seconds: seconds) == text)
    }

    @Test(arguments: [
        (0, "0 seconds"), (1, "1 second"), (45, "45 seconds"), (60, "1 minute"), (61, "1 minute, 1 second"),
        (125, "2 minutes, 5 seconds"),
    ])
    func spokenTimeUsesWholeWords(seconds: Int, text: String) {
        #expect(Countdown.spoken(seconds: seconds) == text)
    }

    @Test func restingCountsDownOneSecondPerSecondBetweenSamples() {
        let sample = RestSample(remainingSeconds: 180.4, sampledAt: start, isResting: true)
        #expect(sample.secondsRemaining(at: start) == 181)
        #expect(sample.secondsRemaining(at: start.addingTimeInterval(0.4)) == 180)
        #expect(sample.secondsRemaining(at: start.addingTimeInterval(1.4)) == 179)
        #expect(sample.secondsRemaining(at: start.addingTimeInterval(500)) == 0)
        #expect(sample.secondsRemaining(at: start.addingTimeInterval(-3)) == 181)
        #expect(sample.end == start.addingTimeInterval(180.4))
    }

    @Test func activityHoldsTheRemainingRestUntilTheNextSample() {
        let sample = RestSample(remainingSeconds: 180.4, sampledAt: start, isResting: false)
        #expect(sample.secondsRemaining(at: start) == 181)
        #expect(sample.secondsRemaining(at: start.addingTimeInterval(4)) == 181)
        #expect(sample.end == nil)
        #expect(RestSample(remainingSeconds: -2, sampledAt: start, isResting: true).secondsRemaining(at: start) == 0)
    }
}
