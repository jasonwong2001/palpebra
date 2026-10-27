import AppKit
import Foundation
import PalpebraCore

/// Drives one rest session from threshold to completion.
///
/// States:
/// - idle: nothing scheduled
/// - preAlert: optional warning one minute before the real popup
/// - running: Core decides elapsed full-screen completion, actual non-blocking rest, or ignored timeout;
///   popup controls can also request a free/challenge skip.
@MainActor
final class BreakCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preAlert
        case running
    }

    @Published private(set) var phase: Phase = .idle

    var onFinished: ((BreakFinishReason) -> Void)?

    private let settings: SettingsStore
    private let store: UsageStore
    private let overlay: BreakOverlayController
    private let mini: MiniReminderController

    private var phaseTimer: Timer?
    private var sessionID: UUID?

    init(
        settings: SettingsStore, store: UsageStore,
        overlay: BreakOverlayController, mini: MiniReminderController
    ) {
        self.settings = settings
        self.store = store
        self.overlay = overlay
        self.mini = mini
    }

    var onBreakStarted: ((AppSettings) -> Date?)?
    var onSessionDeadline: (() -> Void)?
    var onNotificationDelivered: (() -> Void)?
    var onEscapePressed: ((Bool) -> Void)?

    /// Entry point; called by the engine when fatigue hits 100%.
    func begin() {
        guard phase == .idle else { return }
        let s = settings.settings

        if s.preNotification, s.reminderStyle != .notification {
            phase = .preAlert
            Notifier.shared.post(
                id: "palpebra.pre",
                title: "Break in 1 minute",
                body: "Wrap up what you’re doing."
            )
            schedule(60) { [weak self] in self?.startRealBreak() }
        } else {
            startRealBreak()
        }
    }

    /// Pausing reminders cancels a break that is still waiting out its one-minute warning.
    func cancelPending() {
        guard phase == .preAlert else { return }
        phaseTimer?.invalidate()
        phaseTimer = nil
        phase = .idle
    }

    /// Manual "Rest now": never waits behind the pre-alert, and cancels a
    /// pending one.
    func beginManual() {
        switch phase {
        case .running:
            return
        case .preAlert:
            phaseTimer?.invalidate()
            phaseTimer = nil
            startRealBreak(manual: true)
        case .idle:
            startRealBreak(manual: true)
        }
    }

    private func startRealBreak(manual: Bool = false) {
        let s = settings.settings
        phase = .running
        let id = UUID()
        sessionID = id
        let deadline = onBreakStarted?(s)
        store.recordReminder()
        store.recordBreakStart()

        let onSkipFree: () -> Void = { [weak self] in self?.finish(.skippedFree) }
        let onSolved: () -> Void = { [weak self] in self?.finish(.skippedChallenge) }
        let onEscape: (Bool) -> Void = { [weak self] pressed in self?.onEscapePressed?(pressed) }

        switch s.reminderStyle {
        case .fullscreen:
            overlay.show(
                duration: Double(s.breakSeconds),
                skipMode: s.skipMode,
                background: s.popupBackground,
                opacity: s.overlayOpacity,
                headline: s.overlayText,
                onSkipFree: onSkipFree,
                onChallengeSolved: onSolved,
                onEscapePressed: onEscape
            )
        case .mini:
            mini.show(
                skipMode: s.skipMode,
                detectMode: s.detectMode,
                background: s.miniBackground,
                onSkipFree: onSkipFree,
                onChallengeSolved: onSolved,
                onEscapePressed: onEscape
            )
        case .notification:
            Notifier.shared.post(
                id: "palpebra.break.start",
                title: ReminderCopy.startTitle(manual: manual),
                body: ReminderCopy.notificationBody(detectMode: s.detectMode),
                completion: { [weak self] delivered in
                    guard let self, self.phase == .running, self.sessionID == id else { return }
                    if let outcome = BreakFinishReason.notificationOutcome(delivered: delivered) {
                        self.finish(outcome)
                    } else {
                        self.onNotificationDelivered?()
                        if self.phase == .running, let deadline {
                            self.schedule(deadline.timeIntervalSinceNow) { [weak self] in self?.onSessionDeadline?() }
                        }
                    }
                }
            )
            return
        }

        if let deadline {
            schedule(deadline.timeIntervalSinceNow) { [weak self] in self?.onSessionDeadline?() }
        }
    }

    func finish(_ reason: BreakFinishReason) {
        guard phase == .running else { return }
        phaseTimer?.invalidate()
        phaseTimer = nil
        sessionID = nil
        overlay.close()
        mini.close()
        phase = .idle

        store.recordBreakFinish(reason: reason)

        if reason == .completed {
            if settings.settings.breakEndSound {
                if NSSound(named: "Glass")?.play() != true { NSSound.beep() }
            }
            Notifier.shared.post(
                id: "palpebra.break.end",
                title: "Break finished",
                body: "Ease back in when you’re ready."
            )
        }
        onFinished?(reason)
    }

    private func schedule(_ seconds: Double, action: @escaping @MainActor @Sendable () -> Void) {
        phaseTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        phaseTimer = timer
    }
}
