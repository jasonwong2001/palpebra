import Foundation

/// Platform-neutral delivery state used by the notification-style rule and its warning.
package enum NotificationPermission: Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case unavailable

    package var canDeliver: Bool { self == .authorized }

    package var warning: String? {
        switch self {
        case .unknown, .authorized: return nil
        case .notDetermined: return "Palpebra needs permission to send notifications."
        case .denied: return "Notifications are turned off for Palpebra."
        case .unavailable: return "Notifications work in the installed app."
        }
    }
}
