import AppKit

// Development scaffold: render UI previews to PNG and exit.
#if DEBUG
    if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
        index + 1 < CommandLine.arguments.count
    {
        let status: Int32 = MainActor.assumeIsolated {
            defer { AppEnvironment.current.cleanupDevelopmentData() }
            do {
                try PreviewRenderer.run(outputDir: CommandLine.arguments[index + 1])
                return 0
            } catch {
                AppLog.previews.error("Preview rendering failed: \(error)")
                FileHandle.standardError.write(Data("Preview rendering failed: \(error.localizedDescription)\n".utf8))
                return 1
            }
        }
        exit(status)
    }
#endif

// Palpebra — an offline eye-rest assistant for macOS.
// Menu-bar app: no Dock activation, all UI opens on demand.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(environment: .current)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)

    NSApplication.shared.run()
}
