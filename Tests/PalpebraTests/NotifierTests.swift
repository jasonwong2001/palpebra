import Combine
import Foundation
import PalpebraCore
import Testing
import UserNotifications

@testable import Palpebra

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NotifierTests {
    @Test(arguments: [false, true])
    func authorizationCallbackCanArriveOnABackgroundQueue(fails: Bool) async {
        let center = BackgroundNotificationCenter()
        center.authorizationError = fails ? TestError.authorization : nil
        let notifier = Notifier(center: center)

        let permission = await nextPermission(from: notifier) { notifier.requestAuthorization() }

        #expect(permission == .authorized)
        #expect(notifier.deliveryError == (fails ? TestError.authorization.localizedDescription : nil))
        #expect(center.authorizationRequests == 1)
        #expect(center.permissionRequests == 1)
        #expect(center.delegate === notifier)
    }

    @Test(arguments: NotificationSettingsCase.all)
    func settingsCallbackCanArriveOnABackgroundQueue(settings: NotificationSettingsCase) async {
        let center = BackgroundNotificationCenter()
        center.authorizationStatus = settings.status
        center.alertSetting = settings.alertSetting
        let notifier = Notifier(center: center)

        let observed = await nextPermission(from: notifier) { notifier.refreshSettings() }

        #expect(observed == settings.expected)
        #expect(center.permissionRequests == 1)
        #expect(center.authorizationRequests == 0)
    }

    @Test(arguments: NotificationSettingsCase.all)
    func postingHandlesBackgroundSettingsAndReportsDelivery(settings: NotificationSettingsCase) async {
        let center = BackgroundNotificationCenter()
        center.authorizationStatus = settings.status
        center.alertSetting = settings.alertSetting
        let notifier = Notifier(center: center)

        let delivered = await post(using: notifier)

        #expect(delivered == settings.expected.canDeliver)
        #expect(notifier.permission == settings.expected)
        #expect(notifier.deliveryError == nil)
        #expect(center.requests.count == (settings.expected.canDeliver ? 1 : 0))
        if let request = center.requests.first {
            #expect(request.id == "test.break")
            #expect(request.title == "Break finished")
            #expect(request.body == "Rest complete.")
        }
    }

    @Test func postingReportsFailureAfterBackgroundSettingsCallback() async {
        let center = BackgroundNotificationCenter()
        center.deliveryError = TestError.delivery
        let notifier = Notifier(center: center)

        #expect(await post(using: notifier) == false)
        #expect(notifier.deliveryError == "Could not deliver notification: \(TestError.delivery.localizedDescription)")
        #expect(center.requests.count == 1)

        center.deliveryError = nil
        #expect(await post(using: notifier))
        #expect(notifier.deliveryError == nil)
    }

    @Test func unavailableCenterDoesNotRequestSystemPermissionsOrPost() async {
        let notifier = Notifier(center: nil)
        notifier.requestAuthorization()
        #expect(notifier.permission == .unavailable)
        notifier.refreshSettings()
        #expect(notifier.permission == .unavailable)
        #expect(await post(using: notifier) == false)
    }

    private func nextPermission(from notifier: Notifier, action: () -> Void) async -> NotificationPermission {
        var observation: AnyCancellable?
        defer { observation?.cancel() }
        return await withCheckedContinuation { continuation in
            observation = notifier.$permission.dropFirst().first().sink { permission in
                MainActor.assertIsolated()
                continuation.resume(returning: permission)
            }
            action()
        }
    }

    private func post(using notifier: Notifier) async -> Bool {
        await withCheckedContinuation { continuation in
            notifier.post(id: "test.break", title: "Break finished", body: "Rest complete.") { delivered in
                MainActor.assertIsolated()
                continuation.resume(returning: delivered)
            }
        }
    }
}

struct NotificationSettingsCase: Sendable {
    let status: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let expected: NotificationPermission

    static let all: [Self] = [
        .init(status: .notDetermined, alertSetting: .enabled, expected: .notDetermined),
        .init(status: .denied, alertSetting: .enabled, expected: .denied),
        .init(status: .authorized, alertSetting: .enabled, expected: .authorized),
        .init(status: .authorized, alertSetting: .disabled, expected: .denied),
        .init(status: .authorized, alertSetting: .notSupported, expected: .denied),
        .init(status: .provisional, alertSetting: .enabled, expected: .authorized),
        .init(status: .provisional, alertSetting: .disabled, expected: .denied),
    ]
}

private enum TestError: LocalizedError {
    case authorization
    case delivery

    var errorDescription: String? {
        switch self {
        case .authorization: return "Test authorization error"
        case .delivery: return "Test delivery error"
        }
    }
}

@MainActor
private final class BackgroundNotificationCenter: NotificationCenterClient {
    weak var delegate: (any UNUserNotificationCenterDelegate)?
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var alertSetting: UNNotificationSetting = .enabled
    var authorizationError: (any Error)?
    var deliveryError: (any Error)?
    private(set) var authorizationRequests = 0
    private(set) var permissionRequests = 0
    private(set) var requests: [(id: String, title: String, body: String)] = []

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) { self.delegate = delegate }

    func requestAuthorization(completionHandler: @escaping @Sendable (Bool, Error?) -> Void) {
        authorizationRequests += 1
        let error = authorizationError
        DispatchQueue.global().async {
            #expect(!Thread.isMainThread)
            completionHandler(error == nil, error)
        }
    }

    func getSettings(completionHandler: @escaping @Sendable (UNAuthorizationStatus, UNNotificationSetting) -> Void) {
        permissionRequests += 1
        let status = authorizationStatus
        let alertSetting = alertSetting
        DispatchQueue.global().async {
            #expect(!Thread.isMainThread)
            completionHandler(status, alertSetting)
        }
    }

    func add(id: String, title: String, body: String) async throws {
        requests.append((id, title, body))
        if let deliveryError { throw deliveryError }
    }
}
