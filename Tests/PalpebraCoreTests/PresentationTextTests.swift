import PalpebraCore
import Testing

struct PresentationTextTests {
    @Test func displayNumbersHandleInvalidAndOutOfRangeValuesWithoutTrapping() {
        let cases: [(Double, Int)] = [
            (-1, 0), (0, 0), (65.9, 65),
            (.nan, 0), (.infinity, 0), (-.infinity, 0),
            (1e308, Int.max), (.greatestFiniteMagnitude, Int.max),
            (Double(Int.max), Int.max), (Double(Int.max).nextUp, Int.max),
            (Double(Int.max).nextDown, 9_223_372_036_854_774_784),
        ]
        for (value, expected) in cases {
            #expect(DisplayNumber.nonnegativeInteger(value) == expected, "Value: \(value)")
        }
    }

    @Test func aboutUsesBundleMetadataWithAnHonestDevelopmentFallback() {
        #expect(AppVersion.label(version: "2.3.4", build: "17") == "Palpebra 2.3.4 (17)")
        #expect(AppVersion.label(version: "2.3.4", build: nil) == "Palpebra 2.3.4")
        #expect(AppVersion.label(version: nil, build: nil) == "Palpebra — development build")
    }

    @Test(arguments: [
        (0, "0 min"), (1, "1 min"), (45, "45 min"), (59, "59 min"), (60, "1 h"), (61, "1 h 1 min"),
        (220, "3 h 40 min"), (600, "10 h"), (-5, "0 min"),
    ])
    func durationsReadTheSameEverywhere(minutes: Int, text: String) {
        #expect(DurationText.minutes(minutes) == text)
    }

    @Test func measuredDurationsCountWholeMinutesLikeAClock() {
        #expect(DurationText.minutes(45.9) == "45 min")
        #expect(DurationText.minutes(150.0) == "2 h 30 min")
        #expect(DurationText.minutes(Double.nan) == "0 min")
        #expect(DurationText.minutes(-3.0) == "0 min")
    }

    @Test(arguments: [
        (0, "0 minutes"), (1, "1 minute"), (45, "45 minutes"), (60, "1 hour"), (61, "1 hour 1 minute"),
        (220, "3 hours 40 minutes"),
    ])
    func spokenDurationsUseWholeWords(minutes: Int, text: String) {
        #expect(DurationText.spoken(minutes: minutes) == text)
    }

    @Test func nextBreakFollowsTheEngineState() {
        #expect(NextBreak(breakRunning: true, paused: true, minutesToFull: 5) == .running)
        #expect(NextBreak(breakRunning: false, paused: true, minutesToFull: 5) == .paused)
        #expect(NextBreak(breakRunning: false, paused: false, minutesToFull: nil) == .resting)
        #expect(NextBreak(breakRunning: false, paused: false, minutesToFull: 0) == .due)
        #expect(NextBreak(breakRunning: false, paused: false, minutesToFull: 75) == .inMinutes(75))
    }

    @Test func nextBreakHasAValueASpokenFormAndASentence() {
        let cases: [(NextBreak, String, String, String)] = [
            (.running, "Now", "Now", "Break in progress"),
            (.paused, "Paused", "Paused", "Reminders paused"),
            (.resting, "—", "Not counting down while you rest", "Resting"),
            (.due, "Due", "Due", "Break due"),
            (.inMinutes(15), "~15 min", "About 15 minutes", "Next break in ~15 min"),
            (.inMinutes(75), "~1 h 15 min", "About 1 hour 15 minutes", "Next break in ~1 h 15 min"),
        ]
        for (state, value, spoken, sentence) in cases {
            #expect(state.value == value)
            #expect(state.spoken == spoken)
            #expect(state.sentence == sentence)
        }
    }

    /// Always on counts every unlocked minute as use, so only a locked or sleeping Mac rests.
    @Test func restInstructionsMatchTheDetectionMode() {
        #expect(ReminderCopy.restInstruction(detectMode: .smart) == "Look away until this reaches zero.")
        #expect(ReminderCopy.restInstruction(detectMode: .dumb) == "Lock your Mac until this reaches zero.")
        #expect(ReminderCopy.countdownHint(detectMode: .smart) == "Counts down while you look away.")
        #expect(ReminderCopy.countdownHint(detectMode: .dumb) == "Counts down while your Mac is locked.")
        #expect(ReminderCopy.notificationBody(detectMode: .smart) == "Look away from the screen for a few minutes.")
        #expect(ReminderCopy.notificationBody(detectMode: .dumb) == "Lock your Mac for a few minutes to rest.")
    }

    @Test func manualBreaksHaveTheirOwnNotificationTitle() {
        #expect(ReminderCopy.startTitle(manual: true) == "Break started")
        #expect(ReminderCopy.startTitle(manual: false) == "Time to rest your eyes")
    }
}
