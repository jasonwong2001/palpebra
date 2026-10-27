import Combine
import Foundation
import PalpebraCore

/// Samples macOS signals on a timer, publishes Core state and performs its events.
@MainActor
final class FatigueEngine: ObservableObject {
    @Published private(set) var fatigue: Double = 0
    @Published private(set) var isUsingNow = false
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var breakRunning = false
    @Published private(set) var remainingRestSeconds: Double = 0
    /// Minutes until fatigue reaches 100% at the current pace (menu info).
    @Published private(set) var minutesToFull: Int?

    /// Fires after each sample or state change, once the published values and today's usage are current.
    /// `@Published` announces a value before it changes; subscribers here read a finished update.
    let didUpdate = PassthroughSubject<Void, Never>()

    var onThresholdReached: (() -> Void)?
    /// A pause released a reminder that was still waiting out its warning.
    var onPendingBreakCancelled: (() -> Void)?
    var onBreakFinished: ((BreakFinishReason) -> Void)?
    var onManualBreak: (() -> Void)?

    private let settings: SettingsStore
    private let observer: SystemObserver
    private let store: UsageStore

    private var timer: Timer?
    private var emergencyTimer: Timer?
    private var core: FatigueCore
    #if DEBUG
        private var lastTimerTickUptime: TimeInterval?
    #endif

    init(
        settings: SettingsStore, observer: SystemObserver, store: UsageStore
    ) {
        self.settings = settings
        self.observer = observer
        self.store = store
        core = FatigueCore(now: Date())
    }

    var isPaused: Bool { core.isPaused(at: Date()) }
    var canQuitFromMenu: Bool { core.canQuitFromMenu }

    func start() {
        observer.onChange = { [weak self] now in
            guard let self else { return }
            self.tick(at: now)
            // Save usage as the Mac locks or sleeps rather than waiting for the next periodic save.
            if self.observer.screenLocked || self.observer.systemAsleep { self.store.save() }
        }
        core.resetClock(now: Date())
        #if DEBUG
            lastTimerTickUptime = ProcessInfo.processInfo.systemUptime
        #endif
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            // The timer runs on the main run loop, so it is already on the main actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                #if DEBUG
                    self.logTickInterval()
                #endif
                self.tick()
            }
        }
        // A second of leeway lets macOS fire this with other wakeups; Core measures the actual interval.
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        emergencyTimer?.invalidate()
        emergencyTimer = nil
        timer?.invalidate()
        timer = nil
        observer.onChange = nil
        #if DEBUG
            lastTimerTickUptime = nil
        #endif
    }

    #if DEBUG
        /// Measures only the periodic timer; observer/deadline ticks must not hide a delayed timer fire.
        private func logTickInterval() {
            let uptime = ProcessInfo.processInfo.systemUptime
            defer { lastTimerTickUptime = uptime }
            guard let previous = lastTimerTickUptime else { return }
            let interval = uptime - previous
            let locked = observer.screenLocked
            let asleep = observer.systemAsleep
            AppLog.timing.debug(
                "Periodic tick interval_seconds=\(interval, privacy: .public) locked=\(locked, privacy: .public) asleep=\(asleep, privacy: .public)"
            )
        }
    #endif

    private func tick(at now: Date = Date()) {
        let s = settings.settings
        let idle = InputMonitor.idleSeconds() ?? .infinity
        let locked = observer.screenLocked
        let asleep = observer.systemAsleep
        let needsVideo = FatigueCore.needsVideoSignal(inputIdleSeconds: idle, away: locked || asleep, settings: s)
        let signals = FatigueCore.Signals(
            inputIdleSeconds: idle,
            locked: locked,
            asleep: asleep,
            videoPlaying: needsVideo && VideoActivity.displaySleepIsBeingPrevented(),
            activeSecondsToday: store.activeSeconds(on: now),
            notifiedPrimary: store.screenTimeNotified(primary: true, on: now),
            notifiedSecondary: store.screenTimeNotified(primary: false, on: now),
            awayIntervals: observer.takeCompletedAwayIntervals()
        )
        let events = core.step(now: now, signals: signals, settings: s)
        for event in events {
            switch event {
            case .recordActive(let seconds, let fatigue):
                store.recordActive(seconds: seconds, fatigue: fatigue, on: now)
            case .recordFatigued(let seconds):
                store.recordFatigued(seconds: seconds, on: now)
            default:
                break
            }
        }
        publishState()
        for event in events {
            switch event {
            case .thresholdReached:
                onThresholdReached?()
            case .screenTimeReminder(let primary):
                store.setScreenTimeNotified(primary: primary, on: now)
                let hours = primary ? s.screenTimePrimaryHours : s.screenTimeSecondaryHours
                Notifier.shared.post(
                    id: primary ? "palpebra.screentime.primary" : "palpebra.screentime.secondary",
                    title: "\(hours) hours of screen time today",
                    body: "A good moment for a longer break."
                )
            case .breakFinished(let reason):
                emergencyTimer?.invalidate()
                emergencyTimer = nil
                onBreakFinished?(reason)
            case .recordActive, .recordFatigued, .pauseExpired:
                break  // Usage and the cleared pause were applied before reminder delivery.
            }
        }
    }

    private func publishState() {
        if isUsingNow != core.isUsingNow { isUsingNow = core.isUsingNow }
        if fatigue != core.fatigue { fatigue = core.fatigue }
        if pausedUntil != core.pausedUntil { pausedUntil = core.pausedUntil }
        if breakRunning != core.breakRunning { breakRunning = core.breakRunning }
        if minutesToFull != core.minutesToFull { minutesToFull = core.minutesToFull }
        let remaining = core.remainingRestSeconds(settings: settings.settings)
        if remainingRestSeconds != remaining { remainingRestSeconds = remaining }
        didUpdate.send()
    }

    /// The mini reminder's remaining rest, which counts down between samples only while you rest at the Mac.
    var restSample: RestSample {
        let away = observer.screenLocked || observer.systemAsleep
        return RestSample(
            remainingSeconds: remainingRestSeconds, sampledAt: Date(), isResting: !isUsingNow && !isPaused && !away)
    }

    /// Called by the break coordinator after a session finished.
    func completeBreak(reason: BreakFinishReason) {
        emergencyTimer?.invalidate()
        emergencyTimer = nil
        guard core.breakRunning else { return }
        core.completeBreak(reason: reason, at: Date())
        publishState()
    }

    func markBreakRunning(settings: AppSettings) -> Date? {
        core.markBreakRunning(at: Date(), settings: settings)
        publishState()
        return core.sessionDeadline
    }

    func checkSessionDeadline() { tick() }

    func setEscapePressed(_ pressed: Bool) {
        emergencyTimer?.invalidate()
        emergencyTimer = nil
        core.setEscapePressed(pressed, at: Date())
        guard let deadline = core.emergencyExitDeadline else { return }
        let timer = Timer(timeInterval: max(0, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        emergencyTimer = timer
    }

    func markNotificationDelivered() {
        core.markNotificationDelivered()
        tick()
    }

    /// Force a break session now (menu / hotkey / main window).
    func forceBreak() {
        onManualBreak?()
    }

    func pause(until: Date?) {
        let released = core.pause(until: until)
        publishState()
        if released { onPendingBreakCancelled?() }
    }

    #if DEBUG
        /// Sets the published values for documentation previews only; the fatigue model is untouched.
        func showPreviewState(fatigue: Double, isUsing: Bool, minutesToFull: Int?) {
            self.fatigue = fatigue
            self.isUsingNow = isUsing
            self.minutesToFull = minutesToFull
        }
    #endif
}
