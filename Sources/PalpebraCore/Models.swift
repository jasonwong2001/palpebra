import Foundation

// MARK: - Settings enums

/// How a break reminder is delivered when the fatigue threshold is reached.
package enum ReminderStyle: String, Codable, CaseIterable, Sendable {
    case fullscreen
    case mini
    case notification

    package var label: String {
        switch self {
        case .fullscreen: return "Full-screen popup"
        case .mini: return "Mini popup"
        case .notification: return "Notification"
        }
    }
}

/// What the user must do to end a break early.
package enum SkipMode: String, Codable, CaseIterable, Sendable {
    case free
    case challenge
    case locked

    package var label: String {
        switch self {
        case .free: return "Skip freely"
        case .challenge: return "Arithmetic challenge"
        case .locked: return "Cannot skip"
        }
    }
}

/// Usage detection strategy. Smart watches actual input; Always on assumes the
/// computer is in use unless the screen is locked or the system sleeps.
package enum DetectMode: String, Codable, CaseIterable, Sendable {
    case smart
    case dumb

    package var label: String {
        switch self {
        case .smart: return "Smart"
        case .dumb: return "Always on"
        }
    }
}

/// Background look of the break popups.
package enum PopupBackground: String, Codable, CaseIterable, Sendable {
    case auto
    case light
    case dark
    case purple
    case custom

    package var label: String {
        switch self {
        case .auto: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        case .purple: return "Default"
        case .custom: return "Custom image"
        }
    }
}

/// Retained only for legacy decoding/round trips. Individual input switches no longer affect detection.
private struct LegacyDetectChannels: Codable, Equatable, Sendable {
    var keyboard = true
    var mouse = true
    var screenChanges = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyboard = (try? c.decodeIfPresent(Bool.self, forKey: .keyboard)) ?? true
        mouse = (try? c.decodeIfPresent(Bool.self, forKey: .mouse)) ?? true
        screenChanges = (try? c.decodeIfPresent(Bool.self, forKey: .screenChanges)) ?? false
    }
}

// MARK: - Settings

/// The valid range of every numeric setting, shared by decoding and the editing controls.
package enum SettingLimits {
    package static let usageThresholdMinutes = 5...240
    package static let breakSeconds = 20...1800
    package static let reminderIntervalMinutes = 1...60
    package static let idleGraceSeconds = 10...600
    package static let overlayBrightnessPercent = 25...100
    package static let screenTimePrimaryHours = 1...15
    package static let screenTimeSecondaryHours = 2...16

    package static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

/// Persisted reminder, detection and appearance preferences, with per-field decoding defaults.
package struct AppSettings: Codable, Equatable, Sendable {
    // Breaks
    package var usageThresholdMinutes: Int = 45
    package var breakSeconds: Int = 300
    /// Re-remind at most every N minutes while fatigue stays at 100%.
    package var reminderIntervalMinutes: Int = 5
    package var skipMode: SkipMode = .challenge
    package var reminderStyle: ReminderStyle = .fullscreen
    /// Post a system notification one minute before the popup appears.
    package var preNotification: Bool = true

    // Daily screen time
    package var screenTimeReminderEnabled: Bool = false
    package var screenTimePrimaryHours: Int = 4
    package var screenTimeSecondaryHours: Int = 8

    // Detection
    package var detectMode: DetectMode = .smart
    package var countVideoPlayback = false
    private var channels = LegacyDetectChannels()
    /// Input silence after which the user counts as idle.
    package var idleGraceSeconds: Double = 60

    // Appearance
    package var popupBackground: PopupBackground = .purple
    package var miniBackground: PopupBackground = .auto
    package var overlayText: String = ""
    package var overlayOpacity: Double = 0.9
    package var breakEndSound: Bool = true

    // Menu bar / Dock
    package var showDockIcon: Bool = true
    package var statusShowsFatigue: Bool = true
    package var statusShowsHours: Bool = false
    package var statusShowsMinutes: Bool = true
    /// Legacy preference retained for round trips; the duplicate reminder readout is no longer shown.
    package var statusShowsReminderCount: Bool = false

    /// Global shortcut for starting a rest session.
    package var restHotkey: HotKeyCombo?

    // System
    /// Legacy preference retained in the stored schema. The UI reads the login service's current status.
    package var launchAtLogin: Bool = false

    package struct Recovery: Equatable, Sendable {
        package let sourceKey: String
        package let backupKey: String
    }

    /// Loads current settings, falling back to the previous settings key and then defaults.
    /// Unreadable documents are copied before any migration or subsequent edit can replace them.
    /// The caller owns the defaults domain; tests must supply an isolated suite.
    package static func load(
        from defaults: UserDefaults, now: Date = Date(), onRecovery: (Recovery) -> Void = { _ in }
    ) -> AppSettings {
        var settings = AppSettings()
        var hasStoredShortcut = false
        for key in [DefaultsKey.settings, DefaultsKey.legacySettings] {
            guard let data = defaults.data(forKey: key) else { continue }
            do {
                settings = try JSONDecoder().decode(AppSettings.self, from: data)
                let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                hasStoredShortcut = document?.keys.contains("restHotkey") ?? false
                break
            } catch {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let prefix = DefaultsKey.settingsBackupPrefix(for: key) + formatter.string(from: now)
                var backupKey = prefix
                var suffix = 0
                while defaults.object(forKey: backupKey) != nil {
                    suffix += 1
                    backupKey = "\(prefix)-\(suffix)"
                }
                defaults.set(data, forKey: backupKey)
                onRecovery(Recovery(sourceKey: key, backupKey: backupKey))
            }
        }

        let legacyKey = DefaultsKey.legacyRestHotkey
        guard let legacy = defaults.data(forKey: legacyKey) else { return settings }
        if !hasStoredShortcut {
            // The old optional combo was encoded as JSON null when explicitly cleared.
            do {
                settings.restHotkey = try JSONDecoder().decode(HotKeyCombo?.self, from: legacy)
            } catch {
                return settings  // Preserve an unreadable legacy value rather than deleting it.
            }
        }
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: DefaultsKey.settings)
            defaults.removeObject(forKey: legacyKey)
        }
        return settings
    }

    package mutating func setScreenTimePrimaryHours(_ hours: Int) {
        screenTimePrimaryHours = SettingLimits.clamp(hours, to: SettingLimits.screenTimePrimaryHours)
        screenTimeSecondaryHours = min(
            SettingLimits.screenTimeSecondaryHours.upperBound,
            max(screenTimePrimaryHours + 1, screenTimeSecondaryHours))
    }

    package mutating func setScreenTimeSecondaryHours(_ hours: Int) {
        screenTimeSecondaryHours = SettingLimits.clamp(hours, to: SettingLimits.screenTimeSecondaryHours)
        screenTimePrimaryHours = max(
            SettingLimits.screenTimePrimaryHours.lowerBound,
            min(screenTimePrimaryHours, screenTimeSecondaryHours - 1))
    }

    // Missing/malformed fields and unknown enum values fall back independently; extra keys are ignored.
    package init() {}

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usageThresholdMinutes = (try? c.decodeIfPresent(Int.self, forKey: .usageThresholdMinutes)) ?? 45
        breakSeconds = (try? c.decodeIfPresent(Int.self, forKey: .breakSeconds)) ?? 300
        reminderIntervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .reminderIntervalMinutes)) ?? 5
        skipMode = (try? c.decodeIfPresent(SkipMode.self, forKey: .skipMode)) ?? .challenge
        reminderStyle = (try? c.decodeIfPresent(ReminderStyle.self, forKey: .reminderStyle)) ?? .fullscreen
        preNotification = (try? c.decodeIfPresent(Bool.self, forKey: .preNotification)) ?? true
        screenTimeReminderEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .screenTimeReminderEnabled)) ?? false
        screenTimePrimaryHours = (try? c.decodeIfPresent(Int.self, forKey: .screenTimePrimaryHours)) ?? 4
        screenTimeSecondaryHours = (try? c.decodeIfPresent(Int.self, forKey: .screenTimeSecondaryHours)) ?? 8
        detectMode = (try? c.decodeIfPresent(DetectMode.self, forKey: .detectMode)) ?? .smart
        channels = (try? c.decodeIfPresent(LegacyDetectChannels.self, forKey: .channels)) ?? LegacyDetectChannels()
        do {
            countVideoPlayback = try c.decodeIfPresent(Bool.self, forKey: .countVideoPlayback) ?? channels.screenChanges
        } catch {
            countVideoPlayback = false
        }
        idleGraceSeconds = (try? c.decodeIfPresent(Double.self, forKey: .idleGraceSeconds)) ?? 60
        popupBackground = (try? c.decodeIfPresent(PopupBackground.self, forKey: .popupBackground)) ?? .purple
        miniBackground = (try? c.decodeIfPresent(PopupBackground.self, forKey: .miniBackground)) ?? .auto
        overlayText = (try? c.decodeIfPresent(String.self, forKey: .overlayText)) ?? ""
        overlayOpacity = (try? c.decodeIfPresent(Double.self, forKey: .overlayOpacity)) ?? 0.9
        breakEndSound = (try? c.decodeIfPresent(Bool.self, forKey: .breakEndSound)) ?? true
        showDockIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showDockIcon)) ?? true
        statusShowsFatigue = (try? c.decodeIfPresent(Bool.self, forKey: .statusShowsFatigue)) ?? true
        statusShowsHours = (try? c.decodeIfPresent(Bool.self, forKey: .statusShowsHours)) ?? false
        statusShowsMinutes = (try? c.decodeIfPresent(Bool.self, forKey: .statusShowsMinutes)) ?? true
        statusShowsReminderCount = (try? c.decodeIfPresent(Bool.self, forKey: .statusShowsReminderCount)) ?? false
        restHotkey = try? c.decodeIfPresent(HotKeyCombo.self, forKey: .restHotkey)
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? false

        usageThresholdMinutes = SettingLimits.clamp(usageThresholdMinutes, to: SettingLimits.usageThresholdMinutes)
        breakSeconds = SettingLimits.clamp(breakSeconds, to: SettingLimits.breakSeconds)
        reminderIntervalMinutes = SettingLimits.clamp(
            reminderIntervalMinutes, to: SettingLimits.reminderIntervalMinutes)
        let idle = SettingLimits.idleGraceSeconds
        idleGraceSeconds = min(Double(idle.upperBound), max(Double(idle.lowerBound), idleGraceSeconds))
        let brightness = SettingLimits.overlayBrightnessPercent
        overlayOpacity =
            overlayOpacity.isFinite
            ? min(Double(brightness.upperBound) / 100, max(Double(brightness.lowerBound) / 100, overlayOpacity))
            : AppSettings().overlayOpacity
        setScreenTimePrimaryHours(screenTimePrimaryHours)
    }
}

// MARK: - Usage records

/// One calendar day of aggregated usage, the unit the analysis tab renders.
package struct DayRecord: Codable, Equatable, Identifiable, Sendable {
    // Allow ample room for DST, clock changes and legacy day-key collision merges.
    private static let maximumDailySeconds: Double = 7 * 24 * 3600
    private static let maximumDailyCount = 1_000_000

    package private(set) var day: String
    package var activeSeconds: Double = 0
    package var fatiguePeak: Double = 0
    /// Seconds spent with fatigue at or above 80% (the "peak duration" chart).
    package var fatiguedSeconds: Double = 0
    package var breakStarts: Int = 0
    package var breakFinishes: Int = 0
    package var finishReasons: [String] = []
    /// Legacy counter retained in history, but omitted from the UI/CSV because it duplicates breakStarts.
    package var reminderCount: Int = 0
    package var screenTimeNotifiedPrimary = false
    package var screenTimeNotifiedSecondary = false

    package var id: String { day }

    package init(day: String) { self.day = day }

    func rekeyed(to key: String) -> DayRecord {
        var record = self
        record.day = key
        return record
    }

    /// Day-key migration can join two records for the same physical day.
    /// Durations/counts add, a peak remains a maximum, and notification flags remain delivered.
    mutating func mergeUsage(from other: DayRecord) {
        activeSeconds += other.activeSeconds
        fatiguePeak = max(fatiguePeak, other.fatiguePeak)
        fatiguedSeconds += other.fatiguedSeconds
        breakStarts += other.breakStarts
        breakFinishes += other.breakFinishes
        finishReasons += other.finishReasons
        reminderCount += other.reminderCount
        screenTimeNotifiedPrimary = screenTimeNotifiedPrimary || other.screenTimeNotifiedPrimary
        screenTimeNotifiedSecondary = screenTimeNotifiedSecondary || other.screenTimeNotifiedSecondary
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
        fatiguePeak = try c.decodeIfPresent(Double.self, forKey: .fatiguePeak) ?? 0
        fatiguedSeconds = try c.decodeIfPresent(Double.self, forKey: .fatiguedSeconds) ?? 0
        breakStarts = try c.decodeIfPresent(Int.self, forKey: .breakStarts) ?? 0
        breakFinishes = try c.decodeIfPresent(Int.self, forKey: .breakFinishes) ?? 0
        finishReasons = try c.decodeIfPresent([String].self, forKey: .finishReasons) ?? []
        reminderCount = try c.decodeIfPresent(Int.self, forKey: .reminderCount) ?? 0
        screenTimeNotifiedPrimary = try c.decodeIfPresent(Bool.self, forKey: .screenTimeNotifiedPrimary) ?? false
        screenTimeNotifiedSecondary = try c.decodeIfPresent(Bool.self, forKey: .screenTimeNotifiedSecondary) ?? false

        guard
            [activeSeconds, fatiguedSeconds].allSatisfy({ $0.isFinite && (0...Self.maximumDailySeconds).contains($0) }),
            fatiguePeak.isFinite, (0...100).contains(fatiguePeak),
            [breakStarts, breakFinishes, reminderCount].allSatisfy({ (0...Self.maximumDailyCount).contains($0) })
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Usage values exceed supported daily bounds."))
        }
    }
}

/// Persisted outcome of a completed or skipped break session.
package enum BreakFinishReason: String, Codable, Sendable {
    case completed
    case skippedFree
    case skippedChallenge
    case ignored
    case emergency

    /// Undelivered reminders end immediately. Delivered ones still need actual rest.
    package static func notificationOutcome(delivered: Bool) -> BreakFinishReason? {
        delivered ? nil : .ignored
    }
}
