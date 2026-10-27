import Foundation

/// The unit a duration is typed in: a number plus a unit menu, as in Calendar's custom alerts.
package enum DurationUnit: String, CaseIterable, Sendable {
    case seconds, minutes

    package var label: String { self == .seconds ? "sec" : "min" }
    package var seconds: Int { self == .seconds ? 1 : 60 }
}

/// A whole number of seconds shown the way people say it: minutes when it divides evenly, seconds otherwise.
package struct DurationParts: Equatable, Sendable {
    package var value: Int
    package var unit: DurationUnit

    package init(value: Int, unit: DurationUnit) {
        self.value = value
        self.unit = unit
    }

    package init(seconds: Int) {
        if seconds >= 60, seconds % 60 == 0 {
            self.init(value: seconds / 60, unit: .minutes)
        } else {
            self.init(value: seconds, unit: .seconds)
        }
    }

    package var seconds: Int { value * unit.seconds }

    /// A typed number of units in seconds, clamped to the setting's range. A number too large to convert clamps
    /// instead of overflowing, which would crash.
    package static func seconds(typed value: Int, _ unit: DurationUnit, within range: ClosedRange<Int>) -> Int {
        let (seconds, overflow) = value.multipliedReportingOverflow(by: unit.seconds)
        guard !overflow else { return value < 0 ? range.lowerBound : range.upperBound }
        return SettingLimits.clamp(seconds, to: range)
    }

    /// One stepper click: 5-second steps up to a minute, whole minutes above it. Values between
    /// whole minutes snap onto the minute grid, so 90 seconds steps up to 2 minutes and down to 1.
    package static func nudged(_ seconds: Int, by direction: Int, within range: ClosedRange<Int>) -> Int {
        let next: Int
        if seconds > 60 || (seconds == 60 && direction > 0) {
            next = (direction > 0 ? seconds / 60 + 1 : (seconds - 1) / 60) * 60
        } else {
            next = seconds + direction * 5
        }
        return SettingLimits.clamp(next, to: range)
    }
}
