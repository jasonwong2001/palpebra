import AppKit
import Combine
import SwiftUI

/// Follows macOS's rule for app accent colors: Palpebra's violet tints controls only while the system
/// accent is Multicolor (the default). An accent chosen in System Settings → Appearance always wins.
@MainActor
final class AccentPreference: ObservableObject {
    static let shared = AccentPreference()

    @Published private(set) var usesAppAccent = AccentPreference.systemAccentIsMulticolor
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.usesAppAccent = AccentPreference.systemAccentIsMulticolor }
        }
    }

    /// The global `AppleAccentColor` preference is absent while Multicolor is selected.
    private static var systemAccentIsMulticolor: Bool {
        UserDefaults.standard.object(forKey: "AppleAccentColor") == nil
    }

    /// Tint for controls: violet under Multicolor, otherwise nil so they use the user's accent.
    var controlTint: Color? { usesAppAccent ? Palette.controlTint : nil }
    /// Accent-colored text, such as an inline action.
    var textColor: Color { usesAppAccent ? Palette.accent : .accentColor }
}

extension View {
    /// Tints switches, segments, radio buttons and prominent buttons. Push buttons stay gray, as they do
    /// under a native app accent; SwiftUI would otherwise tint them too.
    func appTint(_ color: Color?) -> some View {
        buttonStyle(UntintedButtonStyle()).tint(color)
    }
}

/// The current button style without the tint.
private struct UntintedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).tint(nil)
    }
}

/// Palpebra's visual language, taken from the app icon: a deep-violet tile, a lid-white mark,
/// amber when fatigue is high and coral when a break is due.
enum Palette {
    /// The icon tile's gradient, top-leading to bottom-trailing.
    static let tileTop = Color(red: 0.16, green: 0.10, blue: 0.32)
    static let tileBottom = Color(red: 0.34, green: 0.18, blue: 0.55)
    /// The eyelid mark's white.
    static let lid = Color(red: 0.97, green: 0.94, blue: 1.0)
    /// Soft, low-glare rest grounds and text: a rest screen should never flood the room with pure
    /// white or harsh black.
    static let paper = Color(red: 0.94, green: 0.93, blue: 0.96)
    static let night = Color(red: 0.07, green: 0.06, blue: 0.09)
    static let ink = Color(red: 0.13, green: 0.11, blue: 0.18)

    /// Brand accent for marks and text on window backgrounds: violet in light mode, lavender in dark mode.
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.43, green: 0.27, blue: 0.76, alpha: 1),
        dark: NSColor(srgbRed: 0.72, green: 0.62, blue: 1.0, alpha: 1))
    /// Tint for controls that put white on the color (switches, selected segments, prominent buttons).
    /// White on it is 6.4:1 in light mode and 4.4:1 in dark mode, where the lavender would give 2.2:1,
    /// and it keeps 3:1 against dark form rows.
    static let controlTint = adaptive(
        light: NSColor(srgbRed: 0.43, green: 0.27, blue: 0.76, alpha: 1),
        dark: NSColor(srgbRed: 0.518, green: 0.384, blue: 0.878, alpha: 1))  // #8462E0
    /// High fatigue (80% and above), dark enough for 3:1 contrast on white.
    static let high = adaptive(
        light: NSColor(srgbRed: 0.76, green: 0.48, blue: 0.06, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.43, alpha: 1))
    /// A break is due (100%).
    static let due = adaptive(
        light: NSColor(srgbRed: 0.84, green: 0.25, blue: 0.27, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.48, blue: 0.48, alpha: 1))

    /// Chart marks, validated with the dataviz palette checks (lightness band, chroma floor and color-blind
    /// separation) against the chart cards in each appearance. Dark steps are darker than the UI accents
    /// because bright marks glare on dark surfaces.
    static let chartUse = adaptive(
        light: NSColor(srgbRed: 0.431, green: 0.271, blue: 0.761, alpha: 1),  // #6E45C2
        dark: NSColor(srgbRed: 0.580, green: 0.475, blue: 0.890, alpha: 1))  // #9479E3
    /// The dataviz reference amber. Darkened enough for 3:1 on the light card, amber reads as brown; every bar
    /// is labeled with its value, which the checks accept in place of contrast (1.8:1 light, 4.4:1 dark).
    static let chartHigh = adaptive(
        light: NSColor(srgbRed: 0.929, green: 0.631, blue: 0.0, alpha: 1),  // #EDA100
        dark: NSColor(srgbRed: 0.788, green: 0.522, blue: 0.0, alpha: 1))  // #C98500

    /// The fatigue level's color on window backgrounds.
    static func level(_ fatigue: Double) -> Color {
        fatigue >= 100 ? due : fatigue >= 80 ? high : accent
    }

    /// The fatigue level's color on the violet tile, which looks the same in both appearances.
    static func levelOnTile(_ fatigue: Double) -> Color {
        if fatigue >= 100 { return Color(red: 1.0, green: 0.48, blue: 0.48) }
        if fatigue >= 80 { return Color(red: 1.0, green: 0.78, blue: 0.43) }
        return lid
    }

    /// The icon's tile background, for surfaces that share its look.
    static var tileGradient: LinearGradient {
        LinearGradient(colors: [tileTop, tileBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }
}

/// The closed eyelid from the app icon, normalized to its bounding box (468 × 192 on the icon's
/// 1024 grid). One definition serves the Dock tile, the windows and the menu-bar glyph.
struct EyelidShape: Shape {
    enum Part { case lid, lashes }
    static let aspectRatio: CGFloat = 468 / 192

    var part: Part
    /// Lengthens the lashes for tiny renderings, where the icon's proportions read as a thin squiggle.
    var lashScale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        switch part {
        case .lid:
            path.move(to: point(0, 0))
            path.addCurve(to: point(1, 0), control1: point(0.2265, 0.906), control2: point(0.7735, 0.906))
        case .lashes:
            for (start, end) in [
                ((0.2393, 0.5833), (0.1774, 0.7865)),
                ((0.5, 0.7292), (0.5, 1.0)),
                ((0.7607, 0.5833), (0.8226, 0.7865)),
            ] {
                path.move(to: point(start.0, start.1))
                path.addLine(
                    to: point(
                        start.0 + (end.0 - start.0) * lashScale, start.1 + (end.1 - start.1) * lashScale))
            }
        }
        return path
    }
}

/// The eyelid mark at any size, with the icon's stroke proportions.
struct EyelidMark: View {
    var body: some View {
        GeometryReader { proxy in
            let lineWidth = proxy.size.width * 0.09
            let rect = CGRect(origin: .zero, size: proxy.size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            ZStack {
                EyelidShape(part: .lid).path(in: rect)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                EyelidShape(part: .lashes).path(in: rect)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth * 0.91, lineCap: .round))
            }
        }
        .aspectRatio(EyelidShape.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum StatusGlyph {
    /// The closed-eyelid mark as an 18 pt template image, so the menu bar matches the app icon
    /// instead of showing a generic open eye.
    static func eyelid() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Optical compensation for menu-bar size: a heavier stroke and longer lashes than the icon.
            let lineWidth: CGFloat = 1.9
            let width: CGFloat = 17
            let height = width / EyelidShape.aspectRatio
            let rect = CGRect(
                x: (bounds.width - width) / 2 + lineWidth / 2, y: (bounds.height - height) / 2,
                width: width - lineWidth, height: height - lineWidth)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(lineWidth)
            context.addPath(EyelidShape(part: .lid).path(in: rect).cgPath)
            context.strokePath()
            context.setLineWidth(lineWidth * 0.9)
            context.addPath(EyelidShape(part: .lashes, lashScale: 1.35).path(in: rect).cgPath)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Palpebra"
        return image
    }
}
