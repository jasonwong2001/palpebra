import AppKit
import PalpebraCore
import SwiftUI

@MainActor
final class MainWindowSelection: ObservableObject {
    @Published var tab: MainWindowView.Tab = .today
    /// Analysis keeps its range and granularity while you visit other tabs.
    @Published var analysisRange: AnalysisRange = .week
    @Published var analysisGranularity: AnalysisGranularity = .daily
}

/// Main window shell
@MainActor
struct MainWindowView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: FatigueEngine
    @ObservedObject var store: UsageStore
    @ObservedObject var selection: MainWindowSelection
    var customBackground = CustomBackground.shared
    @ObservedObject private var accent = AccentPreference.shared

    /// How reminders behave (Rules, Detection) comes before the app's own preferences (Settings).
    enum Tab: Hashable, CaseIterable {
        case today, analysis, rules, detection, settings

        var title: String {
            switch self {
            case .today: return "Today"
            case .analysis: return "Analysis"
            case .rules: return "Rules"
            case .detection: return "Detection"
            case .settings: return "Settings"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // A segmented control instead of TabView, whose tab bar ignores the tint and stays system blue.
            Picker("Tabs", selection: $selection.tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .fixedSize()
            .padding(.top, 12)
            .padding(.bottom, 4)

            Group {
                switch selection.tab {
                case .today:
                    TodayView(engine: engine, store: store, settings: settings)
                case .analysis:
                    AnalysisView(
                        store: store, range: $selection.analysisRange,
                        granularity: $selection.analysisGranularity)
                case .rules:
                    RulesView(settings: settings)
                case .detection:
                    DetectionView(settings: settings)
                case .settings:
                    SettingsTabView(settings: settings, store: store, customBackground: customBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
        .appTint(accent.controlTint)
        .alert(
            "Couldn’t save your settings",
            isPresented: Binding(
                get: { settings.saveError != nil },
                set: { if !$0 { settings.saveError = nil } })
        ) {
            Button("OK", role: .cancel) { settings.saveError = nil }
        } message: {
            Text(settings.saveError ?? "")
        }
    }
}

// MARK: - Today

@MainActor
struct TodayView: View {
    @ObservedObject var engine: FatigueEngine
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var accent = AccentPreference.shared

    @State private var showsExplanation = false

    var body: some View {
        let nextBreak = NextBreak(
            breakRunning: engine.breakRunning, paused: engine.isPaused, minutesToFull: engine.minutesToFull)
        let minutes = DisplayNumber.nonnegativeInteger(store.activeSeconds() / 60)
        let breaks = store.breakSummary(last: 1)
        ScrollView {
            VStack(spacing: 28) {
                FatigueRing(fatigue: engine.fatigue, isUsing: engine.isUsingNow)
                    .frame(width: 210, height: 210)
                    .padding(.top, 12)

                HStack(spacing: 0) {
                    stat("Next break", value: nextBreak.value, spoken: nextBreak.spoken)
                    Divider().frame(height: 34)
                    stat(
                        "Screen time", value: DurationText.minutes(minutes),
                        spoken: DurationText.spoken(minutes: minutes))
                    Divider().frame(height: 34)
                    stat(
                        "Breaks today",
                        value: breaks.started == 0 ? "None yet" : "\(breaks.completed) of \(breaks.started)",
                        spoken: breaks.started == 0 ? "None yet" : "\(breaks.completed) of \(breaks.started) completed")
                }
                .frame(maxWidth: 480)

                VStack(spacing: 10) {
                    Button {
                        engine.forceBreak()
                    } label: {
                        Text("Rest now").frame(minWidth: 112)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let until = engine.pausedUntil, engine.isPaused {
                        HStack(spacing: 6) {
                            Text("Reminders paused until \(PauseText.end(until)).")
                                .foregroundStyle(.secondary)
                            // Link-style buttons ignore the tint and stay system blue.
                            Button("Resume") { engine.pause(until: nil) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(accent.textColor)
                        }
                        .font(.callout)
                    }
                }

                DisclosureGroup("How Palpebra works", isExpanded: $showsExplanation) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(explanation, id: \.self) { line in
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 520)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    /// Explains the model with the user's own settings rather than generic N and M.
    private var explanation: [String] {
        let s = settings.settings
        let rise = 100.0 / Double(s.usageThresholdMinutes)
        let decay = 100.0 / (Double(s.breakSeconds) / 60)
        return [
            "Using your Mac raises fatigue by \(percent(rise)) a minute; resting lowers it by \(percent(decay)) a minute.",
            s.detectMode == .smart
                ? "After \(DetectionView.duration(seconds: s.idleGraceSeconds)) without input you count as resting. Locking your Mac counts as rest too."
                : "Your Mac counts as in use until it locks or sleeps.",
            "At 100% a break starts. Full-screen breaks end with their countdown; mini and notification breaks end once fatigue is back to 0%.",
        ]
    }

    private func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))%" : String(format: "%.1f%%", rounded)
    }

    private func stat(_ label: String, value: String, spoken: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }
}

/// Big animated fatigue indicator on Today; the Dock tile shows the same level as a ring.
@MainActor
struct FatigueRing: View {
    let fatigue: Double
    let isUsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The ring fills to the whole percent shown in its center, so it moves, and animates, only when that
        // number changes rather than easing a fraction of a pixel after every five-second sample.
        let percent = min(DisplayNumber.nonnegativeInteger(fatigue), 100)
        let level = Palette.level(fatigue)
        ZStack {
            Circle().stroke(Palette.accent.opacity(0.14), lineWidth: 14)
            Circle()
                .trim(from: 0, to: Double(percent) / 100)
                .stroke(level, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(percent >= 1 ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: percent)
            VStack(spacing: 6) {
                (Text("\(percent)").font(.system(size: 58, weight: .semibold, design: .rounded))
                    + Text("%").font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Circle()
                        .fill(isUsing ? level : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(isUsing ? "In use" : "Resting")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eye fatigue")
        .accessibilityValue("\(percent) percent, \(isUsing ? "in use" : "resting")")
    }
}

// MARK: - Rules (Schedule)

@MainActor
struct RulesView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var notifier = Notifier.shared

    var body: some View {
        Form {
            Section("Breaks") {
                NumberField(
                    title: "Remind me after", value: $settings.settings.usageThresholdMinutes,
                    range: SettingLimits.usageThresholdMinutes, step: 5, unit: "min")
                DurationField(
                    title: "Break length", seconds: $settings.settings.breakSeconds,
                    range: SettingLimits.breakSeconds)
                Picker("Reminder style", selection: $settings.settings.reminderStyle) {
                    ForEach(ReminderStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if settings.settings.reminderStyle == .notification,
                    let warning = notifier.deliveryError ?? notifier.permission.warning
                {
                    Text(warning).font(.footnote).foregroundStyle(.orange)
                    Button("Open Notification Settings") { notifier.openSettings() }
                }
                Picker("Skipping", selection: $settings.settings.skipMode) {
                    ForEach(SkipMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle(
                    "Warn me 1 minute before a break",
                    isOn: $settings.settings.preNotification)
                NumberField(
                    title: "Remind again after a skipped break", value: $settings.settings.reminderIntervalMinutes,
                    range: SettingLimits.reminderIntervalMinutes, unit: "min")
                FormNote(modelSummary)
            }

            Section("Daily screen time") {
                Toggle(
                    "Notify me about long screen days",
                    isOn: $settings.settings.screenTimeReminderEnabled)
                if settings.settings.screenTimeReminderEnabled {
                    NumberField(
                        title: "First notification at",
                        value: Binding(
                            get: { settings.settings.screenTimePrimaryHours },
                            set: { settings.settings.setScreenTimePrimaryHours($0) }),
                        range: SettingLimits.screenTimePrimaryHours, unit: "hours")
                    NumberField(
                        title: "Second notification at",
                        value: Binding(
                            get: { settings.settings.screenTimeSecondaryHours },
                            set: { settings.settings.setScreenTimeSecondaryHours($0) }),
                        range: SettingLimits.screenTimeSecondaryHours, unit: "hours")
                }
            }

        }
        .formStyle(.grouped)
        .onAppear { notifier.refreshSettings() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            notifier.refreshSettings()
        }
    }

    /// The fatigue model in the user's own numbers.
    private var modelSummary: String {
        let s = settings.settings
        let rise = 100.0 / Double(s.usageThresholdMinutes)
        let decay = 100.0 / (Double(s.breakSeconds) / 60)
        return "Each minute of use adds \(Self.percent(rise)) fatigue and each minute of rest removes "
            + "\(Self.percent(decay)). A break starts at 100%."
    }

    private static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))%" : String(format: "%.1f%%", rounded)
    }
}

// MARK: - Detection

@MainActor
struct DetectionView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.settings.detectMode) {
                    ForEach(DetectMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                if settings.settings.detectMode == .smart {
                    DurationField(
                        title: "Count as resting after",
                        seconds: Binding(
                            get: { Int(settings.settings.idleGraceSeconds.rounded()) },
                            set: { settings.settings.idleGraceSeconds = Double($0) }),
                        range: SettingLimits.idleGraceSeconds)
                }
                FormNote(
                    settings.settings.detectMode == .smart
                        ? "Follows your keyboard, mouse and trackpad."
                        : "Counts every minute your Mac is awake and unlocked."
                )
            }

            Section {
                Toggle("Count videos and calls as screen time", isOn: $settings.settings.countVideoPlayback)
                FormNote("Detects apps that keep your display awake, like video players and calls.")
            }
        }
        .formStyle(.grouped)
    }

    static func duration(seconds: Double) -> String {
        let whole = Int(seconds)
        if whole < 60 { return "\(whole) sec" }
        return whole % 60 == 0 ? "\(whole / 60) min" : "\(whole / 60) min \(whole % 60) sec"
    }
}
