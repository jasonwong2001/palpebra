import AppKit
import SwiftUI
import Testing

@testable import Palpebra

/// Rest screens tint their text to suit their background, but the answer field keeps the system's own background,
/// so typed digits must keep the system's text color in every appearance and popup background.
@MainActor
struct ChallengeAnswerStyleTests {
    private func fields(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { fields(in: $0) }
    }

    private func luminance(_ color: NSColor) throws -> CGFloat {
        let c = try #require(color.usingColorSpace(.sRGB))
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    @Test(arguments: [
        (NSAppearance.Name.aqua, "light rest text", true), (.aqua, "dark rest text", false),
        (.darkAqua, "light rest text", true), (.darkAqua, "dark rest text", false),
    ])
    func typedAnswersStayReadableOnTheField(appearance: NSAppearance.Name, _: String, lightRestText: Bool) throws {
        let host = NSHostingView(
            rootView: TextField("Answer", text: .constant("42"))
                .challengeAnswerStyle(compact: false)
                .padding(40)
                .foregroundStyle(lightRestText ? Palette.lid : Palette.ink)
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        host.layoutSubtreeIfNeeded()
        let field = try #require(fields(in: host).first)
        var text = NSColor.textColor
        var background = NSColor.textBackgroundColor
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            text = field.textColor?.usingColorSpace(.sRGB) ?? .textColor
            // A bezeled field fills itself with the system text background for its appearance.
            background = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .textBackgroundColor
        }
        let (a, b) = (try luminance(text), try luminance(background))
        let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        #expect(ratio >= 4.5, "Typed text \(text) on \(background) is \(ratio):1")
    }
}
