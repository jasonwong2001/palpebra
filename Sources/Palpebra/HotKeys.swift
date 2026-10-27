import AppKit
import Carbon.HIToolbox
import PalpebraCore
import SwiftUI

/// Global hotkey: one recorded combo, fired anywhere in the system.
/// Implemented directly on RegisterEventHotKey — no third-party dependency.
@MainActor
final class HotKeyCenter {
    typealias Combo = HotKeyCombo

    var onFired: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    @discardableResult
    func register(_ combo: Combo?) -> String? {
        unregister()
        guard let combo else { return nil }

        // 'PALP' identifies this application's hotkey events.
        let hotKeyID = EventHotKeyID(signature: OSType(0x5041_4C50), id: 1)

        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr else {
            reference = nil
            return "Another app is already using this shortcut."
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                let hp = HotKeyCenter.unmanagedSelf(userData)
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                if hkID.id == 1 {
                    Task { @MainActor in hp.onFired?() }
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else {
            unregister()
            return "Couldn’t set up the shortcut (error \(handlerStatus))."
        }
        return nil
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }

    nonisolated private static func unmanagedSelf(_ pointer: UnsafeMutableRawPointer?) -> HotKeyCenter {
        // The handler runs on the main thread (application event target).
        Unmanaged<HotKeyCenter>.fromOpaque(pointer!).takeUnretainedValue()
    }
}

/// Focusable shortcut recorder. Command combinations arrive through key equivalents;
/// other keys arrive through keyDown. Escape cancels and Delete clears the shortcut.
@MainActor
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: HotKeyCenter.Combo?
    var onRecordingChanged: (Bool) -> Void = { _ in }

    final class RecorderView: NSView {
        var onCombo: ((HotKeyCenter.Combo) -> Void)?
        var onClear: (() -> Void)?
        var onRecordingChanged: ((Bool) -> Void)?
        var combo: HotKeyCenter.Combo? {
            didSet {
                needsDisplay = true
                setAccessibilityValue(combo?.display ?? "No shortcut")
            }
        }
        private var needsModifier = false
        /// Fits the longest prompt, "Include ⌘/⌥/⌃/⇧" (108 pt), with a text field's 6 pt insets, at a text field's
        /// height. A recorded shortcut is shorter still, so a wider field would stand mostly empty.
        static let size = NSSize(width: 120, height: 21)

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { Self.size }
        override var focusRingMaskBounds: NSRect { bounds }

        required init?(coder: NSCoder) { fatalError("unsupported") }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            focusRingType = .exterior
            setAccessibilityElement(true)
            setAccessibilityRole(.textField)
            setAccessibilityLabel("Rest now shortcut")
            setAccessibilityHelp("Click and press a key with a modifier. Escape cancels; Delete clears.")
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            needsModifier = false
            needsDisplay = true
            onRecordingChanged?(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            guard super.resignFirstResponder() else { return false }
            needsModifier = false
            needsDisplay = true
            onRecordingChanged?(false)
            return true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let names = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification]
            for name in names {
                NotificationCenter.default.removeObserver(self, name: name, object: nil)
            }
            guard let window else {
                onRecordingChanged?(false)
                return
            }
            for name in names {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowLostFocus), name: name, object: window)
            }
        }

        @objc private func windowLostFocus(_ notification: Notification) {
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }

        override func draw(_ dirtyRect: NSRect) {
            // The 1 pt border lies just inside the bounds, so the field's edges meet a text field's.
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            NSColor.textBackgroundColor.setFill()
            border.fill()
            NSColor.separatorColor.setStroke()
            border.stroke()

            let focused = window?.firstResponder === self
            let text =
                needsModifier
                ? "Include ⌘/⌥/⌃/⇧" : (focused ? "Press shortcut…" : (combo?.display ?? "Click to record"))
            // A compact control you click, so its text centers like a button's label, and a recorded shortcut sits
            // in the middle like a key cap. The 4 pt insets are a system text field's: a 2 pt bezel plus 2 pt of
            // line padding.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: focused || combo == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                in: NSRect(
                    x: 4, y: (bounds.height - size.height) / 2, width: max(0, bounds.width - 8), height: size.height),
                withAttributes: attributes)
        }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }

        override func flagsChanged(with event: NSEvent) {
            // Bare modifier transitions do not record a shortcut or beep.
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.type == .keyDown else { return false }
            capture(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            capture(event)
        }

        private func capture(_ event: NSEvent) {
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }

            switch HotKeyCombo.recordingAction(keyCode: UInt32(event.keyCode), modifiers: modifiers) {
            case .cancel:
                window?.makeFirstResponder(nil)
            case .clear:
                combo = nil
                onClear?()
                window?.makeFirstResponder(nil)
            case .requiresModifier:
                needsModifier = true
                needsDisplay = true
            case .combo(let value):
                combo = value
                onCombo?(value)
                window?.makeFirstResponder(nil)
            }
        }
    }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    /// A fixed-size control, whatever width the form offers.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecorderView, context: Context) -> CGSize? {
        RecorderView.size
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        let binding = $combo
        nsView.onCombo = { binding.wrappedValue = $0 }
        nsView.onClear = { binding.wrappedValue = nil }
        nsView.onRecordingChanged = onRecordingChanged
        nsView.combo = combo
    }

    /// SwiftUI dismantles the recorder while it destroys the view graph, and publishing a settings change from there
    /// aborts the app (an exclusive-access violation in SwiftUI). Report the end of recording once teardown is over.
    static func dismantleNSView(_ nsView: RecorderView, coordinator: ()) {
        guard let onRecordingChanged = nsView.onRecordingChanged else { return }
        nsView.onRecordingChanged = nil
        Task { @MainActor in onRecordingChanged(false) }
    }
}
