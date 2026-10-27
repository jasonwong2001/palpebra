#if DEBUG
    import Foundation

    /// Chooses isolated storage before a development entry point constructs any app stores.
    package enum DevelopmentHooks {
        package static func requiresIsolatedStorage(arguments: [String], environment: [String: String]) -> Bool {
            arguments.contains("--render-previews")
                || environment["PALPEBRA_SELFTEST"] == "1"
                || environment["PALPEBRA_OPEN_MAIN"] == "1"
        }
    }

    /// Owns one disposable defaults suite and data directory; it never reads the app's real defaults or files.
    package final class DevelopmentStorage {
        package let directory: URL
        package let defaults: UserDefaults
        private let suiteName: String
        private let onCleanupError: @Sendable (Error) -> Void

        package init(onCleanupError: @escaping @Sendable (Error) -> Void) throws {
            self.onCleanupError = onCleanupError
            let id = UUID().uuidString
            suiteName = "org.palpebra.development.\(id)"
            guard let defaults = UserDefaults(suiteName: suiteName) else { throw StorageError.defaultsUnavailable }
            self.defaults = defaults
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "palpebra-\(id)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        package func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            do {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            } catch {
                onCleanupError(error)
            }
        }

        deinit { cleanup() }

        private enum StorageError: Error {
            case defaultsUnavailable
        }
    }
#endif
