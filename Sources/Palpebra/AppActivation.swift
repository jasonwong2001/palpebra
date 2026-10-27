import AppKit

extension NSApplication {
    /// Uses the current activation API while retaining macOS 13 support.
    @MainActor func activateForInteraction() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
