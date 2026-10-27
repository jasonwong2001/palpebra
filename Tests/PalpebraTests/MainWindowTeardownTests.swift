import AppKit
import PalpebraCore
import SwiftUI
import Testing

@testable import Palpebra

/// Closing the main window destroys its SwiftUI views. Nothing they do on the way out may publish a change to the
/// graph being destroyed: SwiftUI aborts on that. Stores use a disposable directory and defaults suite, and the
/// window is never shown.
@MainActor
struct MainWindowTeardownTests {
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("palpebra-\(UUID().uuidString)")
        let suiteName = "org.palpebra.tests.\(UUID().uuidString)"
        let settings: SettingsStore
        let store: UsageStore
        let engine: FatigueEngine

        @MainActor init() throws {
            settings = SettingsStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
            store = UsageStore(directory: directory)
            engine = FatigueEngine(settings: settings, observer: SystemObserver(), store: store)
        }

        deinit {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func find<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    /// Opens the window's content, then closes it the way the app does: ending editing, then releasing the content
    /// in a later task, once the window has left the screen.
    private func openAndClose(tab: MainWindowView.Tab, focusing focus: ((NSWindow) throws -> Void)? = nil)
        async throws -> Fixture
    {
        let fixture = try Fixture()
        let selection = MainWindowSelection()
        selection.tab = tab
        let background = CustomBackground(fileURL: fixture.directory.appendingPathComponent("popup-background"))
        let controller = MainWindowController {
            NSHostingController(
                rootView: MainWindowView(
                    settings: fixture.settings, engine: fixture.engine, store: fixture.store, selection: selection,
                    customBackground: background))
        }
        autoreleasepool { controller.attachContent() }
        let window = try #require(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try focus?(window)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.contentViewController == nil)
        return fixture
    }

    @Test(arguments: MainWindowView.Tab.allCases)
    func closingTheWindowTearsDownEachTab(tab: MainWindowView.Tab) async throws {
        _ = try await openAndClose(tab: tab)
    }

    /// The shortcut recorder is an AppKit view that reports when recording starts and ends, while the window's root
    /// view observes the same settings. Closing the window after it had focus once aborted the app, depending on
    /// when SwiftUI flushed its pending updates, so the test closes it many times.
    @Test func closingTheWindowAfterRecordingAShortcutTearsDownSafely() async throws {
        for _ in 0..<20 {
            let fixture = try await openAndClose(tab: .settings) { window in
                let content = try #require(window.contentView)
                let recorder = try #require(Self.find(HotKeyRecorder.RecorderView.self, in: content))
                #expect(window.makeFirstResponder(recorder))
            }
            #expect(!fixture.settings.isRecordingHotkey)
        }
    }
}
