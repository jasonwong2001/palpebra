import AppKit

/// Handles Esc only in the focused rest window. Release or loss of focus cancels the continuous hold.
@MainActor
final class EscapeHoldHandler {
    private var pressed = false
    private let onChanged: (Bool) -> Void

    init(onChanged: @escaping (Bool) -> Void) { self.onChanged = onChanged }

    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown || event.type == .keyUp, event.keyCode == 53 else { return false }
        if event.type == .keyDown {
            if !pressed, !event.isARepeat {
                pressed = true
                onChanged(true)
            }
        } else {
            cancel()
        }
        return true
    }

    func cancel() {
        guard pressed else { return }
        pressed = false
        onChanged(false)
    }
}
