/// Whole-number labels shared by usage, fatigue and rest views.
package enum DisplayNumber {
    package static func nonnegativeInteger(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        // Double(Int.max) rounds up on 64-bit platforms, so compare before converting.
        guard value < Double(Int.max) else { return Int.max }
        return Int(value)
    }
}
