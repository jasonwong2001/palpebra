import IOKit.pwr_mgt

/// Coarse, permission-free signal: video players/calls and keep-awake tools can hold this assertion.
@MainActor
enum VideoActivity {
    static func displaySleepIsBeingPrevented() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
            let assertions = status?.takeRetainedValue() as? [String: Int]
        else { return false }
        return (assertions["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }
}
