import AppKit

/// Owns the main window. Its SwiftUI content exists only while the window is open: a closed window's views
/// would otherwise keep re-rendering after every sample. The window itself, and the frame you gave it, persist.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private static let initialContentSize = NSSize(width: 760, height: 560)

    private let makeContent: () -> NSViewController
    private(set) var window: NSWindow?

    init(makeContent: @escaping () -> NSViewController) {
        self.makeContent = makeContent
        super.init()
    }

    func show() {
        attachContent()
        NSApp.activateForInteraction()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Creates the window on first use and rebuilds its content after a close, keeping the frame.
    func attachContent() {
        let window = self.window ?? makeWindow()
        self.window = window
        guard window.contentViewController == nil else { return }
        let frame = window.frame
        window.contentViewController = makeContent()
        window.setFrame(frame, display: false)
    }

    func releaseContentIfClosed() {
        guard let window, !window.isVisible, window.contentViewController != nil else { return }
        let frame = window.frame
        window.contentViewController = nil
        window.setFrame(frame, display: false)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.title = "Palpebra"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Ends editing, so a number typed without pressing Return still applies, then releases the content once
    /// the window has left the screen.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        Task { @MainActor [weak self] in self?.releaseContentIfClosed() }
    }
}
