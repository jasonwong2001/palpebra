import Foundation
import os

/// Log categories share the running bundle's identifier, including development bundles.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Palpebra"
    static let history = Logger(subsystem: subsystem, category: "History")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let background = Logger(subsystem: subsystem, category: "Background")
    static let actions = Logger(subsystem: subsystem, category: "Actions")
    #if DEBUG
        static let development = Logger(subsystem: subsystem, category: "Development")
        static let previews = Logger(subsystem: subsystem, category: "Previews")
        static let timing = Logger(subsystem: subsystem, category: "Timing")
    #endif
}
