#if DEBUG
    import AppKit
    import PalpebraCore
    import SwiftUI

    /// Development scaffold: renders key views offscreen to PNG files so UI
    /// changes can be verified without screen-recording permission.
    /// Usage: Palpebra --render-previews /path/to/output-dir
    enum PreviewRenderer {
        @MainActor static func run(outputDir: String) throws {
            let dir = URL(fileURLWithPath: outputDir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let environment = AppEnvironment.current
            precondition(environment.isDevelopment, "Previews require isolated development storage.")
            let settings = SettingsStore(defaults: environment.defaults)
            let store = UsageStore(directory: environment.dataDirectory, filename: "preview.json")
            seed(store)
            let engine = FatigueEngine(settings: settings, observer: SystemObserver(), store: store)
            engine.showPreviewState(fatigue: 67, isUsing: true, minutesToFull: 15)
            // Unbundled DEBUG runs have no app icon, so the Dock preview reads the committed artwork.
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let icon =
                NSImage(contentsOf: repository.appendingPathComponent("Resources/AppIcon.png"))
                ?? NSApp.applicationIconImage ?? NSImage()

            let app = NSApplication.shared
            let originalAppearance = app.appearance
            defer { app.appearance = originalAppearance }
            for scheme in [ColorScheme.light, .dark] {
                app.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                // Main-window views take the app accent, as under the default Multicolor setting; the
                // rest screens aren't tinted.
                try snapshot(
                    TodayView(engine: engine, store: store, settings: settings).appTint(Palette.controlTint),
                    size: CGSize(width: 640, height: 460), name: "today", scheme: scheme, dir: dir)
                try snapshot(
                    HStack(spacing: 20) {
                        ForEach([0.0, 45, 85, 100], id: \.self) { level in
                            DockTileView(fatigue: level, icon: icon).frame(width: 96, height: 96)
                        }
                    }, size: CGSize(width: 480, height: 136), name: "dock", scheme: scheme, dir: dir)
                try snapshot(
                    BreakOverlayView(
                        endsAt: Date().addingTimeInterval(120),
                        skipMode: .challenge,
                        background: .purple,
                        headline: "",
                        onSkipFree: {}, onChallengeSolved: {}
                    ), size: CGSize(width: 640, height: 400), name: "overlay-fullscreen", scheme: scheme, dir: dir,
                    // Mostly a dithered gradient, which PNG stores at about 1 MB; JPEG keeps it near 70 KB.
                    jpeg: true)
                try snapshot(
                    MiniReminderView(
                        progress: RestProgress(
                            sample: RestSample(remainingSeconds: 180, sampledAt: Date(), isResting: true)),
                        skipMode: .challenge,
                        detectMode: .smart,
                        background: .auto,
                        onSkipFree: {}, onChallengeSolved: {}
                    ), size: CGSize(width: 340, height: 254), name: "mini-reminder", scheme: scheme, dir: dir)
                try snapshot(
                    DetectionView(settings: settings).appTint(Palette.controlTint),
                    size: CGSize(width: 560, height: 560), name: "detection", scheme: scheme, dir: dir)
                try snapshot(
                    RulesView(settings: settings).appTint(Palette.controlTint),
                    size: CGSize(width: 720, height: 640), name: "rules", scheme: scheme, dir: dir)
                try snapshot(
                    SettingsTabView(settings: settings, store: store).appTint(Palette.controlTint),
                    size: CGSize(width: 720, height: 1080), name: "settings", scheme: scheme, dir: dir)
                try snapshot(
                    AnalysisView(store: store, range: .constant(.week), granularity: .constant(.daily))
                        .appTint(Palette.controlTint),
                    size: CGSize(width: 660, height: 740), name: "analysis", scheme: scheme, dir: dir)
            }
        }

        @MainActor static func seed(_ store: UsageStore) {
            let offsets = Array(0..<10) + [30, 60, 300, 369]
            let dailyMinutes = [220, 310, 180, 400, 260, 340, 150, 290, 370, 240]
            for (index, dayOffset) in offsets.enumerated() {
                let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date())!
                let minutes = Double(dailyMinutes[index % dailyMinutes.count])
                store.recordActive(seconds: minutes * 60, fatigue: 50, on: date)
                store.recordFatigued(seconds: minutes * 12, on: date)
                store.recordBreakStart(on: date)
                store.recordBreakFinish(reason: dayOffset % 3 == 0 ? .skippedChallenge : .completed, on: date)
                store.recordReminder(on: date)
            }
        }

        @MainActor private static func snapshot<V: View>(
            _ view: V, size: CGSize, name: String, scheme: ColorScheme, dir: URL, jpeg: Bool = false
        ) throws {
            let host = NSHostingController(
                rootView:
                    view
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme))
            host.view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.view.setFrameSize(size)
            host.view.layoutSubtreeIfNeeded()

            // Two pixels per point: the README shows each image at its width in points, so Retina displays draw
            // them sharp. The window background fills every pixel.
            let bounds = host.view.bounds
            let scale = 2
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                )
            else { throw RenderError.bitmapUnavailable(name) }
            rep.size = bounds.size
            host.view.cacheDisplay(in: bounds, to: rep)
            guard
                let data = jpeg
                    ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    : rep.representation(using: .png, properties: [:])
            else {
                throw RenderError.encodingUnavailable(name)
            }
            let variant = scheme == .dark ? "dark" : "light"
            try data.write(
                to: dir.appendingPathComponent("\(name)-\(variant).\(jpeg ? "jpg" : "png")"), options: .atomic)
        }

        private enum RenderError: LocalizedError {
            case bitmapUnavailable(String)
            case encodingUnavailable(String)

            var errorDescription: String? {
                switch self {
                case .bitmapUnavailable(let name): return "Could not allocate the preview bitmap for \(name)."
                case .encodingUnavailable(let name): return "Could not encode the preview image for \(name)."
                }
            }
        }
    }
#endif
