import UserNotifications

/// Declares the background callback contract even on SDKs without Sendable annotations.
/// Injection keeps tests independent of the system center and the user's permissions.
@MainActor
protocol NotificationCenterClient: Sendable {
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate)
    func requestAuthorization(completionHandler: @escaping @Sendable (Bool, Error?) -> Void)
    func getSettings(completionHandler: @escaping @Sendable (UNAuthorizationStatus, UNNotificationSetting) -> Void)
    func add(id: String, title: String, body: String) async throws
}

struct SystemNotificationCenterClient: NotificationCenterClient {
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
    }

    nonisolated func requestAuthorization(completionHandler: @escaping @Sendable (Bool, Error?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound], completionHandler: completionHandler)
    }

    nonisolated func getSettings(
        completionHandler: @escaping @Sendable (UNAuthorizationStatus, UNNotificationSetting) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
            completionHandler(settings.authorizationStatus, settings.alertSetting)
        }
    }

    func add(id: String, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
