import PalpebraCore
import Testing

struct DurationTests {
    @Test(arguments: [
        (300, 5, DurationUnit.minutes), (60, 1, .minutes), (1800, 30, .minutes),
        (90, 90, .seconds), (20, 20, .seconds), (45, 45, .seconds),
    ])
    func secondsReadTheWayPeopleSayThem(seconds: Int, value: Int, unit: DurationUnit) {
        let parts = DurationParts(seconds: seconds)
        #expect(parts == DurationParts(value: value, unit: unit))
        #expect(parts.seconds == seconds)
    }

    @Test(arguments: [
        (7, DurationUnit.minutes, 420), (20, .seconds, 20), (5, .seconds, 20), (45, .minutes, 1800), (0, .minutes, 20),
        (Int.max, .minutes, 1800), (Int.max / 60 + 1, .minutes, 1800), (Int.min, .minutes, 20), (-5, .seconds, 20),
    ])
    func typedDurationsClampWithoutOverflowing(value: Int, unit: DurationUnit, seconds: Int) {
        #expect(DurationParts.seconds(typed: value, unit, within: SettingLimits.breakSeconds) == seconds)
    }

    @Test(arguments: [
        (55, 1, 60), (60, 1, 120), (60, -1, 55), (90, 1, 120), (90, -1, 60),
        (120, -1, 60), (25, -1, 20), (20, -1, 20), (1800, 1, 1800),
    ])
    func stepperMovesInSecondsBelowAMinuteAndWholeMinutesAbove(seconds: Int, direction: Int, expected: Int) {
        #expect(DurationParts.nudged(seconds, by: direction, within: SettingLimits.breakSeconds) == expected)
    }
}
