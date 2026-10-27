import AppKit
import Combine
import PalpebraCore

/// Menu-bar item: configurable live readout plus the command menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let statusItem: NSStatusItem

    struct Actions {
        var openMain: () -> Void
        var startBreak: () -> Void
        var pause: (Date?) -> Void
        var quit: () -> Void
    }

    private let actions: Actions
    private let engine: FatigueEngine
    private let store: UsageStore
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(engine: FatigueEngine, store: UsageStore, settings: SettingsStore, actions: Actions) {
        self.engine = engine
        self.store = store
        self.settings = settings
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.image = StatusGlyph.eyelid()
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("Palpebra")
        }

        // Each engine update (every sample, pause and break change) is already final when it arrives, and it
        // also covers screen time recorded while fatigue is frozen. Settings arrive before they change.
        engine.didUpdate.sink { [weak self] in self?.refresh() }.store(in: &cancellables)
        settings.$settings.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        refresh()
    }

    private var nextBreak: NextBreak {
        NextBreak(breakRunning: engine.breakRunning, paused: engine.isPaused, minutesToFull: engine.minutesToFull)
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let s = settings.settings
        let fatigue = DisplayNumber.nonnegativeInteger(engine.fatigue)
        let minutes = DisplayNumber.nonnegativeInteger(store.activeSeconds() / 60)

        var segments: [String] = []
        if s.statusShowsFatigue { segments.append("\(fatigue)%") }
        if s.statusShowsHours { segments.append("\(minutes / 60)h") }
        if s.statusShowsMinutes { segments.append("\(minutes % 60)m") }
        if engine.isPaused { segments.append("⏸") }
        let title = segments.joined(separator: " ")
        // Most samples change nothing you can see; only a changed title is worth redrawing the menu bar for.
        if button.title != title { button.title = title }

        let nextBreak = nextBreak
        let toolTip = [
            "Fatigue \(fatigue)%", "Screen time today: \(DurationText.minutes(minutes))",
            nextBreak.sentence(pausedUntil: engine.pausedUntil),
        ].joined(separator: "\n")
        guard button.toolTip != toolTip else { return }
        button.toolTip = toolTip
        button.setAccessibilityValue(
            "Fatigue \(fatigue) percent. Screen time today: \(DurationText.spoken(minutes: minutes)). "
                + "Next break: \(nextBreak.spoken).")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // A glance before the commands; items without an action show as information.
        let fatigue = DisplayNumber.nonnegativeInteger(engine.fatigue)
        let glance = "Fatigue \(fatigue)% · \(nextBreak.sentence(pausedUntil: engine.pausedUntil))"
        menu.addItem(NSMenuItem(title: glance, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Screen time today: \(usageText)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let main = NSMenuItem(
            title: "Open Palpebra", action: #selector(mainTapped), keyEquivalent: "n"
        )
        main.target = self
        menu.addItem(main)

        let breakItem = NSMenuItem(
            title: "Rest now", action: #selector(startBreakTapped), keyEquivalent: "r"
        )
        breakItem.target = self
        menu.addItem(breakItem)

        menu.addItem(pauseItem())
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Palpebra", action: #selector(quitTapped), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    private var usageText: String {
        DurationText.minutes(store.activeSeconds() / 60)
    }

    private func pauseItem() -> NSMenuItem {
        if engine.isPaused {
            let item = NSMenuItem(
                title: "Resume reminders",
                action: #selector(resumeTapped), keyEquivalent: ""
            )
            item.target = self
            return item
        }
        let item = NSMenuItem(
            title: "Pause reminders", action: nil, keyEquivalent: ""
        )
        let submenu = NSMenu()
        var options: [(String, Int?)] = [
            ("30 minutes", 30),
            ("1 hour", 60),
            ("2 hours", 120),
            ("6 hours", 360),
            ("Until tomorrow", nil),
        ]
        #if DEBUG
            options.insert(("Pause 2 min", 2), at: 0)
            options.insert(("Pause 1 min", 1), at: 0)
        #endif
        for (label, minutesOpt) in options {
            let sub = NSMenuItem(
                title: label, action: #selector(pauseTapped(_:)), keyEquivalent: ""
            )
            sub.target = self
            sub.tag = minutesOpt ?? -1
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    // MARK: actions

    @objc private func mainTapped() { actions.openMain() }
    @objc private func startBreakTapped() { actions.startBreak() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(quitTapped) ? engine.canQuitFromMenu : true
    }

    @objc private func quitTapped() {
        guard engine.canQuitFromMenu else { return }
        actions.quit()
    }
    @objc private func resumeTapped() { actions.pause(nil) }

    @objc private func pauseTapped(_ sender: NSMenuItem) {
        if sender.tag == -1 {
            let tomorrow = Calendar.current.startOfDay(
                for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            )
            actions.pause(tomorrow)
        } else {
            actions.pause(Date().addingTimeInterval(Double(sender.tag) * 60))
        }
    }
}
