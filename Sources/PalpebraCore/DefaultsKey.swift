/// UserDefaults keys are part of the stored schema; keep their existing spelling across releases.
package enum DefaultsKey {
    package static let settings = "palpebra.settings.v2"
    package static let legacySettings = "palpebra.settings.v1"
    package static let legacyRestHotkey = "palpebra.restHotkey"
    package static let onboarded = "palpebra.onboarded"

    package static func settingsBackupPrefix(for key: String) -> String {
        "\(key).corrupt-"
    }
}
