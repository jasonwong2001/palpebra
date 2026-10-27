import AppKit
import PalpebraCore

/// Records wall-clock rest intervals from system state changes:
/// screen lock (DistributedNotificationCenter) and sleep (NSWorkspace).
@MainActor
final class SystemObserver: ObservableObject {
    private var state = AwayState()
    var screenLocked: Bool { state.locked }
    var systemAsleep: Bool { state.systemAsleep || state.displayAsleep }
    var onChange: ((Date) -> Void)?

    func takeCompletedAwayIntervals() -> [DateInterval] { state.takeCompletedIntervals() }

    private func update(_ signal: AwayState.Signal, active: Bool) {
        let now = Date()
        state.set(signal, active: active, at: now)
        onChange?(now)
    }

    private var observations: [NotificationObservation] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observations = [
            NotificationObservation(center: distributed, name: NSNotification.Name("com.apple.screenIsLocked")) {
                [weak self] in self?.update(.lock, active: true)
            },
            NotificationObservation(center: distributed, name: NSNotification.Name("com.apple.screenIsUnlocked")) {
                [weak self] in self?.update(.lock, active: false)
            },
            NotificationObservation(center: workspace, name: NSWorkspace.willSleepNotification) { [weak self] in
                self?.update(.systemSleep, active: true)
            },
            NotificationObservation(center: workspace, name: NSWorkspace.didWakeNotification) { [weak self] in
                self?.update(.systemSleep, active: false)
            },
            NotificationObservation(center: workspace, name: NSWorkspace.screensDidSleepNotification) { [weak self] in
                self?.update(.displaySleep, active: true)
            },
            NotificationObservation(center: workspace, name: NSWorkspace.screensDidWakeNotification) { [weak self] in
                self?.update(.displaySleep, active: false)
            },
        ]
    }
}

/// Owns only a Foundation registration, so teardown needs no actor-isolated app state.
/// NotificationCenter supports removing observers from any thread, including during deinitialization.
private final class NotificationObservation {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, name: Notification.Name, action: @escaping @MainActor @Sendable () -> Void) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            // The explicit main operation queue guarantees synchronous MainActor delivery.
            MainActor.assumeIsolated { action() }
        }
    }

    deinit { center.removeObserver(token) }
}
