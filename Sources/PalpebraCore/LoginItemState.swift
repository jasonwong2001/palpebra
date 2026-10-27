import Foundation

/// Current system state. The legacy stored launch-at-login preference is retained only for decoding compatibility.
package enum LoginItemState: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable

    package var isEnabled: Bool { self == .enabled }

    package var approvalHint: String? {
        self == .requiresApproval ? "Approve in System Settings → General → Login Items" : nil
    }
}
