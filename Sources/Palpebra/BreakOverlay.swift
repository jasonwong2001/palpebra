import AppKit
import ImageIO
import PalpebraCore
import SwiftUI

/// Shared popup background: match-system / light / dark / default (deep
/// violet) / custom image picked by the user (copied into App Support).
@MainActor
struct PopupBackgroundView<Content: View>: View {
    let style: PopupBackground
    let content: Content
    @ObservedObject private var customBackground = CustomBackground.shared

    @Environment(\.colorScheme) private var scheme

    init(style: PopupBackground, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        ZStack {
            Group {
                switch style {
                case .auto:
                    (scheme == .dark ? Palette.night : Palette.paper).ignoresSafeArea()
                case .light:
                    Palette.paper.ignoresSafeArea()
                case .dark:
                    Palette.night.ignoresSafeArea()
                case .purple:
                    Palette.tileGradient.ignoresSafeArea()
                case .custom:
                    if let image = customBackground.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            // A scrim keeps the text readable on any photo.
                            .overlay(Color.black.opacity(0.35))
                            .ignoresSafeArea()
                    } else {
                        Palette.night.ignoresSafeArea()
                    }
                }
            }
            .accessibilityHidden(true)
            content
        }
        .foregroundStyle(textColor)
    }

    private var textColor: Color {
        switch style {
        case .light: return Palette.ink
        case .auto: return scheme == .dark ? Palette.lid : Palette.ink
        default: return Palette.lid
        }
    }
}

@MainActor
final class CustomBackground: ObservableObject {
    static let shared = CustomBackground(
        fileURL: AppEnvironment.current.dataDirectory.appendingPathComponent("popup-background"))

    private let fileURL: URL
    @Published private(set) var image: NSImage?
    /// Reading and decoding a large photo can take most of a second, so it runs off the main thread. Each choice
    /// bumps the generation, so a slower, older load never replaces a newer one.
    private var generation = 0
    private var loading: Task<Void, Never>?
    /// The latest write or removal. The next one waits for it, so the file ends up holding the latest choice.
    private var fileChange: Task<Void, Error>?

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let screens = Self.screenPixelSizes()
        loading = Task { [weak self] in
            do {
                let image = try await Task.detached(priority: .utility) {
                    try Self.decode(Data(contentsOf: fileURL), screens: screens)
                }.value
                self?.show(image, generation: 0)
            } catch {
                AppLog.background.error("Could not load the custom background image: \(error)")
            }
        }
    }

    /// Waits until the saved image found at creation has loaded.
    func loaded() async {
        await loading?.value
    }

    /// Copies the picked image into App Support so it survives picker runs.
    func adopt(_ url: URL) async throws {
        generation += 1
        let current = generation
        let screens = Self.screenPixelSizes()
        let (data, image) = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            return (data, try Self.decode(data, screens: screens))
        }.value
        guard current == generation else { return }
        try await changeFile { fileURL in
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        }
        show(image, generation: current)
    }

    func remove() async throws {
        generation += 1
        let current = generation
        try await changeFile { fileURL in
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
        if current == generation { image = nil }
    }

    private func changeFile(_ change: @escaping @Sendable (URL) throws -> Void) async throws {
        let previous = fileChange
        let fileURL = self.fileURL
        let task = Task.detached(priority: .userInitiated) {
            _ = await previous?.result
            try change(fileURL)
        }
        fileChange = task
        try await task.value
    }

    private func show(_ image: CGImage, generation: Int) {
        guard generation == self.generation else { return }
        self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func screenPixelSizes() -> [CGSize] {
        NSScreen.screens.map { screen in
            CGSize(
                width: screen.frame.width * screen.backingScaleFactor,
                height: screen.frame.height * screen.backingScaleFactor)
        }
    }

    /// Decodes once, upright, at the size that fills the screens. A 48-megapixel photo would otherwise stay
    /// decoded at full size, around 190 MB, for as long as Palpebra runs, and be scaled down on every break.
    nonisolated private static func decode(_ data: Data, screens: [CGSize]) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            // A format only AppKit can read keeps its full size.
            guard let image = NSImage(data: data), image.isValid,
                let decoded = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { throw ImageError.invalidImage }
            return decoded
        }
        // Orientations 5 to 8 turn the picture a quarter, swapping its width and height on screen.
        let turned = (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        let size = turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: ImageFill.pixelSize(image: size, screens: screens),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageError.invalidImage
        }
        return image
    }

    private enum ImageError: LocalizedError {
        case invalidImage

        var errorDescription: String? { "Choose a PNG, JPEG, HEIC or other standard image file." }
    }
}

/// Borderless windows refuse keyboard input unless they can become key;
/// the skip challenge's answer field needs exactly that.
@MainActor
final class BreakOverlayWindow: NSWindow {
    var escapeHold: EscapeHoldHandler?
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if escapeHold?.handle(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        escapeHold?.cancel()
        super.resignKey()
    }
}

/// Owns one borderless window per screen for the full-screen rest overlay.
@MainActor
final class BreakOverlayController {
    private var windows: [NSWindow] = []

    func show(
        duration: Double,
        skipMode: SkipMode,
        background: PopupBackground,
        opacity: Double,
        headline: String,
        onSkipFree: @escaping () -> Void,
        onChallengeSolved: @escaping () -> Void,
        onEscapePressed: @escaping (Bool) -> Void
    ) {
        close()
        let endsAt = Date().addingTimeInterval(duration)

        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        var keyCandidate: NSWindow?
        for screen in NSScreen.screens {
            let view = BreakOverlayView(
                endsAt: endsAt,
                skipMode: skipMode,
                background: background,
                headline: headline,
                onSkipFree: onSkipFree,
                onChallengeSolved: onChallengeSolved
            )
            .opacity(opacity)

            let window = BreakOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: view)
            if skipMode == .locked { window.escapeHold = EscapeHoldHandler(onChanged: onEscapePressed) }
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
            if screen == mouseScreen { keyCandidate = window }
        }
        NSApp.activateForInteraction()
        (keyCandidate ?? windows.first)?.makeKeyAndOrderFront(nil)
        RestTransition.fadeIn(windows)
    }

    func close() {
        RestTransition.fadeOut(windows)
        windows.removeAll()
    }

    var isVisible: Bool { !windows.isEmpty }
}

/// Rest surfaces ease in and out instead of snapping over what you were doing.
@MainActor
enum RestTransition {
    static func fadeIn(_ windows: [NSWindow]) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in windows { window.animator().alphaValue = 1 }
        }
    }

    /// Windows stop taking clicks at once and leave the screen when the fade ends.
    static func fadeOut(_ windows: [NSWindow]) {
        guard !windows.isEmpty else { return }
        for window in windows { window.ignoresMouseEvents = true }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in windows { window.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                for window in windows { window.orderOut(nil) }
            }
        }
    }
}

/// Full-screen rest surface: countdown, optional custom headline, and the
/// skip affordance gated by the configured skip mode.
@MainActor
struct BreakOverlayView: View {
    let endsAt: Date
    let skipMode: SkipMode
    let background: PopupBackground
    let headline: String
    let onSkipFree: () -> Void
    let onChallengeSolved: () -> Void

    @State private var showingChallenge = false
    @FocusState private var skipFocused: Bool

    var body: some View {
        PopupBackgroundView(style: background) {
            VStack(spacing: 28) {
                if showingChallenge {
                    SkipChallengeView(onSolved: onChallengeSolved) {
                        showingChallenge = false
                        skipFocused = true
                    }
                } else {
                    EyelidMark()
                        .frame(width: 64)
                        .opacity(0.85)

                    Text(headline.isEmpty ? "Rest your eyes" : headline)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    CountdownText(endsAt: endsAt)
                        .font(.system(size: 104, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.92)

                    Text("Stand up, stretch, and look into the distance.")
                        .font(.title3)
                        .opacity(0.72)

                    skipControl
                        .padding(.top, 6)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($skipFocused, true)
    }

    @ViewBuilder
    private var skipControl: some View {
        switch skipMode {
        case .locked:
            Text("Emergency? Hold Esc for 5 seconds.")
                .font(.caption).opacity(0.7)
        case .free:
            // Deliberately quiet: on a rest screen, skipping shouldn't be the most inviting action.
            Button("Skip this break", action: onSkipFree)
                .buttonStyle(.bordered)
                .focusable()
                .focused($skipFocused)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityHint("Press Command-S to skip this break.")
        case .challenge:
            Button("Solve a puzzle to skip") {
                showingChallenge = true
            }
            .buttonStyle(.bordered)
            .focusable()
            .focused($skipFocused)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityHint("Press Command-S to open the arithmetic challenge.")
        }
    }
}

@MainActor
struct CountdownText: View {
    let endsAt: Date

    var body: some View {
        // Updates land on each whole second before the end, so a two-minute rest opens on 2:00.
        TimelineView(.periodic(from: Countdown.scheduleStart(until: endsAt, at: Date()), by: 1)) { context in
            let remaining = Countdown.secondsRemaining(until: endsAt, at: context.date)
            Text(Countdown.text(seconds: remaining))
                .accessibilityLabel("Rest time remaining")
                .accessibilityValue(Countdown.spoken(seconds: remaining))
        }
    }
}

extension View {
    /// The skip challenge's answer field: large, centered digits. The field keeps the system's own background, so
    /// typed digits take the system text color. The hierarchical `.primary` would inherit the rest screen's tint
    /// instead, near-white on the purple screen, and vanish against a white field.
    func challengeAnswerStyle(compact: Bool) -> some View {
        textFieldStyle(.roundedBorder)
            .frame(width: compact ? 130 : 200)
            .font(.system(size: compact ? 15 : 20, design: .rounded))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.primary)
    }
}

/// Arithmetic gate: two random terms; a wrong answer swaps in a new puzzle.
@MainActor
struct SkipChallengeView: View {
    let onSolved: () -> Void
    let onCancel: () -> Void
    /// Smaller type and controls for the mini reminder's card.
    var compact = false

    private struct Puzzle {
        let question: String
        let answer: Int
    }

    @State private var puzzle = Puzzle(question: "12 + 34", answer: 46)
    @State private var input = ""
    @State private var wrongAttempt = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: compact ? 10 : 20) {
            Text("Solve to skip")
                .font(.system(size: compact ? 14 : 26, weight: .semibold, design: .rounded))
                .opacity(0.85)

            Text("\(puzzle.question) = ?")
                .font(.system(size: compact ? 30 : 56, weight: .light, design: .rounded))
                .monospacedDigit()

            TextField("Answer", text: $input)
                .challengeAnswerStyle(compact: compact)
                .accessibilityLabel("Answer to \(puzzle.question)")
                .accessibilityHint("Press Return to submit the answer.")
                .focused($fieldFocused)
                .onSubmit(submit)

            if wrongAttempt {
                Text("Not quite. Here’s a new one.")
                    .font(compact ? .caption : .callout)
                    .opacity(0.8)
            }

            HStack(spacing: compact ? 8 : 12) {
                Button("Submit and skip", action: submit)
                    .focusable()
                Button("Keep resting", action: onCancel)
                    .focusable()
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .controlSize(compact ? .small : .large)
        }
        .onAppear {
            newPuzzle()
            fieldFocused = true
            // the break may have started without the app being active; the
            // answer field is useless without the keyboard
            NSApp.activateForInteraction()
        }
    }

    private func newPuzzle() {
        let a = Int.random(in: 12...89)
        let b = Int.random(in: 12...89)
        if Bool.random() {
            puzzle = Puzzle(question: "\(a) + \(b)", answer: a + b)
        } else {
            let small = Int.random(in: 3...9)
            let large = Int.random(in: 4...12)
            puzzle = Puzzle(question: "\(small) × \(large)", answer: small * large)
        }
    }

    private func submit() {
        if let value = Int(input.trimmingCharacters(in: .whitespaces)), value == puzzle.answer {
            onSolved()
        } else {
            wrongAttempt = true
            input = ""
            newPuzzle()
        }
    }
}
