import AppKit
import PalpebraCore
import SwiftUI

@MainActor
final class RestProgress: ObservableObject {
    @Published var sample: RestSample

    init(sample: RestSample) { self.sample = sample }
}

@MainActor
final class MiniReminderPanel: NSPanel {
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

/// Compact always-on-top rest card above the Dock, with the same skip rules as the full-screen
/// overlay. It is a borderless, movable card rather than a titled window.
@MainActor
final class MiniReminderController {
    static let cardSize = NSSize(width: 300, height: 214)

    private var panel: NSPanel?
    private let progress = RestProgress(sample: RestSample(remainingSeconds: 0, sampledAt: Date(), isResting: false))

    func update(_ sample: RestSample) { progress.sample = sample }

    func show(
        skipMode: SkipMode,
        detectMode: DetectMode,
        background: PopupBackground,
        onSkipFree: @escaping () -> Void,
        onChallengeSolved: @escaping () -> Void,
        onEscapePressed: @escaping (Bool) -> Void
    ) {
        close()
        let view = MiniReminderView(
            progress: progress,
            skipMode: skipMode,
            detectMode: detectMode,
            background: background,
            onSkipFree: onSkipFree,
            onChallengeSolved: onChallengeSolved
        )

        let panel = MiniReminderPanel(
            contentRect: NSRect(origin: .zero, size: Self.cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Rest reminder"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: view)
        if skipMode == .locked { panel.escapeHold = EscapeHoldHandler(onChanged: onEscapePressed) }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        if let screen = NSScreen.main {
            // The visible frame excludes the Dock and menu bar, whatever their size or position.
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - Self.cardSize.width / 2, y: area.minY + 24))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        RestTransition.fadeIn([panel])
        self.panel = panel
    }

    func close() {
        if let panel { RestTransition.fadeOut([panel]) }
        panel = nil
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}

@MainActor
struct MiniReminderView: View {
    @ObservedObject var progress: RestProgress
    let skipMode: SkipMode
    /// What counts as rest, and so what the card asks you to do.
    let detectMode: DetectMode
    let background: PopupBackground
    let onSkipFree: () -> Void
    let onChallengeSolved: () -> Void

    @State private var showingChallenge = false
    @FocusState private var skipFocused: Bool

    private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        PopupBackgroundView(style: background) {
            VStack(spacing: 6) {
                if showingChallenge {
                    SkipChallengeView(
                        onSolved: onChallengeSolved,
                        onCancel: {
                            showingChallenge = false
                            skipFocused = true
                        },
                        compact: true)
                } else {
                    EyelidMark()
                        .frame(width: 34)
                        .opacity(0.85)
                        .padding(.bottom, 2)
                    Text("Rest your eyes")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    remainingRest
                    Text(ReminderCopy.restInstruction(detectMode: detectMode))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .opacity(0.7)
                    skipControl
                        .padding(.top, 6)
                }
            }
            .padding(18)
        }
        .frame(width: MiniReminderController.cardSize.width, height: MiniReminderController.cardSize.height)
        .clipShape(card)
        .overlay(card.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .defaultFocus($skipFocused, true)
    }

    /// The engine samples every few seconds; while you rest, the card counts down every second in between,
    /// changing as each whole second of the sampled rest passes.
    private var remainingRest: some View {
        let sample = progress.sample
        let start = Countdown.scheduleStart(until: sample.end ?? sample.sampledAt, at: Date())
        return TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = sample.secondsRemaining(at: context.date)
            Text(Countdown.text(seconds: seconds))
                .font(.system(size: 46, weight: .thin, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Rest time remaining")
                .accessibilityValue(Countdown.spoken(seconds: seconds))
                .accessibilityHint(ReminderCopy.countdownHint(detectMode: detectMode))
        }
    }

    @ViewBuilder
    private var skipControl: some View {
        switch skipMode {
        case .locked:
            Text("Emergency? Hold Esc for 5 seconds.")
                .font(.caption).opacity(0.7)
        case .free:
            Button("Skip this break", action: onSkipFree)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable()
                .focused($skipFocused)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityHint("Press Command-S to skip this break.")
        case .challenge:
            Button("Solve a puzzle to skip") {
                showingChallenge = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .focusable()
            .focused($skipFocused)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityHint("Press Command-S to open the arithmetic challenge.")
        }
    }
}
