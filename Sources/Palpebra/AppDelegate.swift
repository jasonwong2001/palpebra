import AppKit
import Combine
import PalpebraCore
import SwiftUI

/// Assembles the object graph and owns the on-demand windows.
///
/// Settings -> SystemObserver/UsageStore -> FatigueEngine -> BreakCoordinator
/// Status bar, Dock ring and the main window observe engine/store/settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    let settings: SettingsStore
    let observer = SystemObserver()
    lazy var store = UsageStore(directory: environment.dataDirectory)
    lazy var engine = FatigueEngine(settings: settings, observer: observer, store: store)
    lazy var overlay = BreakOverlayController()
    lazy var mini = MiniReminderController()
    lazy var coordinator = BreakCoordinator(settings: settings, store: store, overlay: overlay, mini: mini)

    private var statusBar: StatusBarController?
    private let dockIcon = DockIconController()
    private let hotKeys = HotKeyCenter()

    private let mainSelection = MainWindowSelection()
    private lazy var mainWindow = MainWindowController { [settings, engine, store, mainSelection] in
        NSHostingController(
            rootView: MainWindowView(settings: settings, engine: engine, store: store, selection: mainSelection))
    }
    private var mainMenu: MainMenuController?
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        settings = SettingsStore(defaults: environment.defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Construct and install the retained notification delegate before any reminder can be posted.
        Notifier.shared.requestAuthorization()
        // Start loading a custom background now, off the main thread, so the first break shows it at once.
        _ = CustomBackground.shared

        mainMenu = MainMenuController(
            canQuit: { [weak self] in self?.engine.canQuitFromMenu ?? true },
            openSettings: { [weak self] in
                self?.mainSelection.tab = .settings
                self?.openMainWindow()
            })

        hotKeys.onFired = { [weak self] in self?.engine.forceBreak() }
        settings.$settings.map(\.restHotkey)
            .combineLatest(settings.$isRecordingHotkey)
            .map { combo, recording in recording ? nil : combo }
            .removeDuplicates()
            .sink { [weak self] combo in
                guard let self else { return }
                self.settings.hotkeyRegistrationError = self.hotKeys.register(combo)
            }
            .store(in: &cancellables)

        engine.onThresholdReached = { [weak self] in
            self?.coordinator.begin()
        }
        engine.onManualBreak = { [weak self] in
            self?.coordinator.beginManual()
        }
        engine.onPendingBreakCancelled = { [weak self] in self?.coordinator.cancelPending() }
        coordinator.onBreakStarted = { [weak self] settings in
            self?.engine.markBreakRunning(settings: settings)
        }
        engine.onBreakFinished = { [weak self] reason in self?.coordinator.finish(reason) }
        coordinator.onSessionDeadline = { [weak self] in self?.engine.checkSessionDeadline() }
        coordinator.onNotificationDelivered = { [weak self] in self?.engine.markNotificationDelivered() }
        coordinator.onEscapePressed = { [weak self] pressed in self?.engine.setEscapePressed(pressed) }
        coordinator.onFinished = { [weak self] reason in
            self?.engine.completeBreak(reason: reason)
        }
        engine.didUpdate
            .sink { [weak self] in
                guard let self else { return }
                self.mini.update(self.engine.restSample)
            }
            .store(in: &cancellables)

        settings.$settings
            .map(\.showDockIcon)
            .removeDuplicates()
            .sink { visible in
                NSApp.setActivationPolicy(visible ? .regular : .accessory)
            }
            .store(in: &cancellables)

        statusBar = StatusBarController(
            engine: engine,
            store: store,
            settings: settings,
            actions: .init(
                openMain: { [weak self] in self?.openMainWindow() },
                startBreak: { [weak self] in self?.engine.forceBreak() },
                pause: { [weak self] until in self?.engine.pause(until: until) },
                quit: { NSApp.terminate(nil) }
            )
        )

        dockIcon.attach(to: engine, settings: settings)
        #if DEBUG
            if ProcessInfo.processInfo.environment["PALPEBRA_OPEN_MAIN"] == "1" {
                PreviewRenderer.seed(store)
            }
        #endif
        engine.start()

        var shouldOpenMain = !environment.defaults.bool(forKey: DefaultsKey.onboarded)
        #if DEBUG
            shouldOpenMain = shouldOpenMain || ProcessInfo.processInfo.environment["PALPEBRA_OPEN_MAIN"] == "1"
        #endif
        if shouldOpenMain {
            openMainWindow()
            environment.defaults.set(true, forKey: DefaultsKey.onboarded)
        }

        #if DEBUG
            // Automated smoke test: manual rest must show the overlay within a
            // second (no pre-alert wait). PALPEBRA_SELFTEST=1 Palpebra
            if ProcessInfo.processInfo.environment["PALPEBRA_SELFTEST"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.coordinator.beginManual()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        let visible = (self?.overlay.isVisible ?? false) || (self?.mini.isVisible ?? false)
                        let running = self?.coordinator.phase == .running
                        let keyIsOverlay = NSApp.keyWindow is BreakOverlayWindow
                        print(
                            "SELFTEST overlayVisible=\(visible) keyIsOverlay=\(keyIsOverlay) phase=\(String(describing: self?.coordinator.phase))"
                        )
                        self?.engine.stop()
                        self?.store.save()
                        self?.environment.cleanupDevelopmentData()
                        exit(visible && running && keyIsOverlay ? 0 : 3)
                    }
                }
            }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // menu-bar app stays alive
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        store.save()
        environment.cleanupDevelopmentData()
    }

    // MARK: main window

    func openMainWindow() {
        mainWindow.show()
    }
}
