import AppKit
import SwiftUI
import Testing

@testable import Palpebra

@MainActor
private final class RenderCounter: ObservableObject {
    @Published var value = 0
    var bodies = 0
}

/// Flexible, like the main window's tabs, so the window keeps the size it's given.
@MainActor
private struct CountingView: View {
    @ObservedObject var counter: RenderCounter

    var body: some View {
        counter.bodies += 1
        return Text("\(counter.value)").frame(minWidth: 300, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
    }
}

/// The window is never ordered on screen; these tests only attach and release its content. Each step runs in its
/// own autorelease pool, as a pass of the app's run loop would.
@MainActor
struct MainWindowControllerTests {
    private func drainMainRunLoop() {
        for _ in 0..<3 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    @Test func closedWindowsReleaseTheirContentAndStopRendering() throws {
        let counter = RenderCounter()
        let controller = MainWindowController { NSHostingController(rootView: CountingView(counter: counter)) }
        weak var content: NSViewController?
        autoreleasepool {
            controller.attachContent()
            content = controller.window?.contentViewController
            counter.value += 1
        }
        drainMainRunLoop()
        let window = try #require(controller.window)
        let frame = window.frame
        #expect(content != nil)
        #expect(counter.bodies > 0)

        autoreleasepool { controller.releaseContentIfClosed() }
        drainMainRunLoop()
        #expect(window.contentViewController == nil)
        #expect(content == nil)
        let bodies = counter.bodies
        for _ in 0..<5 { counter.value += 1 }
        drainMainRunLoop()
        #expect(counter.bodies == bodies)
        #expect(window.frame == frame)
    }

    @Test func reopeningRebuildsTheContentAtTheSameFrame() throws {
        let counter = RenderCounter()
        var built = 0
        let controller = MainWindowController {
            built += 1
            return NSHostingController(rootView: CountingView(counter: counter))
        }
        controller.attachContent()
        controller.attachContent()
        #expect(built == 1)
        let window = try #require(controller.window)
        let frame = NSRect(x: 40, y: 60, width: 900, height: 640)
        window.setFrame(frame, display: false)
        drainMainRunLoop()
        controller.releaseContentIfClosed()
        drainMainRunLoop()
        controller.attachContent()
        drainMainRunLoop()
        #expect(built == 2)
        #expect(window.contentViewController != nil)
        #expect(window.frame == frame)
    }
}
