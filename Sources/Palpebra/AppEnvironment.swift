import Foundation
import PalpebraCore

/// Chooses storage once, before any controller, settings object or background cache is constructed.
@MainActor
final class AppEnvironment {
    static let current = AppEnvironment()

    let defaults: UserDefaults
    let dataDirectory: URL
    let isDevelopment: Bool
    #if DEBUG
        private let developmentStorage: DevelopmentStorage?
    #endif

    private init() {
        #if DEBUG
            if DevelopmentHooks.requiresIsolatedStorage(
                arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
            {
                do {
                    let storage = try DevelopmentStorage { error in
                        AppLog.development.error("Could not remove isolated development data: \(error)")
                    }
                    developmentStorage = storage
                    defaults = storage.defaults
                    dataDirectory = storage.directory
                    isDevelopment = true
                    return
                } catch {
                    fatalError("Could not create isolated development storage: \(error)")
                }
            }
            developmentStorage = nil
        #endif
        defaults = .standard
        dataDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Palpebra", isDirectory: true)
        isDevelopment = false
    }

    func cleanupDevelopmentData() {
        #if DEBUG
            developmentStorage?.cleanup()
        #endif
    }
}
