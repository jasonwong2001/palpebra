import AppKit
import Combine
import PalpebraCore
import UserNotifications

/// Queries delivery permissions before posting. Bare development binaries cannot use UserNotifications.
@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier(center: isBundled ? SystemNotificationCenterClient() : nil)

    @Published private(set) var permission: NotificationPermission = .unknown
    @Published private(set) var deliveryError: String?

    private let center: (any NotificationCenterClient)?

    private static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && !AppEnvironment.current.isDevelopment
    }

    init(center: (any NotificationCenterClient)?) {
        self.center = center
        super.init()
        // The center holds its delegate weakly; the shared notifier retains it for the app's lifetime.
        center?.setDelegate(self)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func requestAuthorization() {
        guard let center else {
            permission = .unavailable
            return
        }
        center.requestAuthorization { @Sendable [weak self] _, error in
            Task { @MainActor in
                self?.deliveryError = error?.localizedDescription
                self?.refreshSettings()
            }
        }
    }

    func refreshSettings() {
        guard let center else {
            permission = .unavailable
            return
        }
        center.getSettings { @Sendable [weak self] status, alertSetting in
            let permission = Self.permission(for: status, alertSetting: alertSetting)
            Task { @MainActor in self?.permission = permission }
        }
    }

    nonisolated private static func permission(
        for status: UNAuthorizationStatus, alertSetting: UNNotificationSetting
    ) -> NotificationPermission {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional:
            return alertSetting == .enabled ? .authorized : .denied
        @unknown default: return .denied
        }
    }

    func post(
        id: String, title: String, body: String,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        guard let center else {
            permission = .unavailable
            completion?(false)
            return
        }
        center.getSettings { @Sendable [weak self] status, alertSetting in
            let permission = Self.permission(for: status, alertSetting: alertSetting)
            Task { @MainActor in
                guard let self else { return }
                self.permission = permission
                guard self.permission.canDeliver else {
                    completion?(false)
                    return
                }
                do {
                    try await center.add(id: id, title: title, body: body)
                    self.deliveryError = nil
                    completion?(true)
                } catch {
                    self.deliveryError = "Could not deliver notification: \(error.localizedDescription)"
                    completion?(false)
                }
            }
        }
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        if !NSWorkspace.shared.open(url) {
            deliveryError = "Could not open notification settings."
        }
    }
}
