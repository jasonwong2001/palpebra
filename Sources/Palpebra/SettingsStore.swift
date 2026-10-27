import Combine
import Foundation
import PalpebraCore

/// Settings persisted to UserDefaults as JSON, additive & idempotent on load.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    let recoveries: [AppSettings.Recovery]

    @Published var hotkeyRegistrationError: String?
    @Published var isRecordingHotkey = false
    @Published var saveError: String?

    @Published var settings: AppSettings {
        didSet {
            guard oldValue != settings else { return }
            save()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var recoveries: [AppSettings.Recovery] = []
        settings = AppSettings.load(from: defaults, now: Date()) { recovery in
            recoveries.append(recovery)
            AppLog.settings.error(
                "Could not decode \(recovery.sourceKey, privacy: .public); preserved original settings at \(recovery.backupKey, privacy: .public)"
            )
        }
        self.recoveries = recoveries
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: DefaultsKey.settings)
            saveError = nil
        } catch {
            AppLog.settings.error("Could not encode settings: \(error)")
            saveError = "Could not save settings: \(error.localizedDescription)"
        }
    }
}
