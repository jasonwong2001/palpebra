import AppKit
import Combine
import PalpebraCore
import SwiftUI

/// Renders live fatigue on the Dock tile as a ring around the app icon's eyelid.
@MainActor
final class DockIconController {
    private var hostingView: NSHostingView<DockTileView>?
    private var cancellable: AnyCancellable?

    func attach(to engine: FatigueEngine, settings: SettingsStore) {
        cancellable = engine.$fatigue
            .combineLatest(settings.$settings.map(\.showDockIcon))
            .map { fatigue, visible in visible ? DisplayNumber.nonnegativeInteger(fatigue) : nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] percentage in self?.update(percentage: percentage) }
    }

    private func update(percentage: Int?) {
        let tile = NSApp.dockTile
        guard let percentage else {
            tile.contentView = nil
            hostingView = nil
            tile.display()
            return
        }
        let view = DockTileView(fatigue: Double(percentage), icon: NSApp.applicationIconImage)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
            tile.contentView = hostingView
            self.hostingView = hostingView
        }
        hostingView?.layoutSubtreeIfNeeded()
        tile.display()
    }
}

/// The app icon itself, with fatigue drawn as a ring around the eyelid, so the Dock keeps showing
/// Palpebra rather than a generic widget. The ring is white while fatigue is normal, amber from 80%
/// and coral when a break is due.
@MainActor
struct DockTileView: View {
    let fatigue: Double
    let icon: NSImage

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // On the icon's 1024 grid the eyelid fits inside a radius of about 250, and the tile body
            // ends at 412; a ring of radius 325 sits between them.
            let diameter = side * 0.636
            let lineWidth = side * 0.042
            ZStack {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)
                if fatigue >= 1 {
                    Circle()
                        .trim(from: 0, to: min(fatigue, 100) / 100)
                        .stroke(
                            Palette.levelOnTile(fatigue),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter, height: diameter)
                        .shadow(color: .black.opacity(0.2), radius: side * 0.01, y: side * 0.004)
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eye fatigue")
        .accessibilityValue("\(DisplayNumber.nonnegativeInteger(fatigue)) percent")
    }
}
