import Foundation

/// The persisted Carbon shortcut schema and its English display.
package struct HotKeyCombo: Equatable, Codable, Sendable {
    package var keyCode: UInt32
    package var modifiers: UInt32  // Carbon modifier mask

    package var display: String {
        var parts: [String] = []
        if modifiers & Modifier.control != 0 { parts.append("⌃") }
        if modifiers & Modifier.option != 0 { parts.append("⌥") }
        if modifiers & Modifier.shift != 0 { parts.append("⇧") }
        if modifiers & Modifier.command != 0 { parts.append("⌘") }
        parts.append(Self.keyString(keyCode))
        return parts.joined()
    }

    // kVK_ANSI_* letter/digit positions and kVK_Space/Return/Escape/Tab from HIToolbox/Events.h.
    static func keyString(_ code: UInt32) -> String {
        switch Int(code) {
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 49: return "Space"
        case 36: return "↩"
        case 53: return "⎋"
        case 48: return "⇥"
        default: return "Key\(code)"
        }
    }

    /// Carbon Events.h modifier bits; kept here so Core needs only Foundation.
    package enum Modifier: Sendable {
        package static let command: UInt32 = 1 << 8
        package static let shift: UInt32 = 1 << 9
        package static let option: UInt32 = 1 << 11
        package static let control: UInt32 = 1 << 12
        package static let mask = command | shift | option | control
    }

    /// HIToolbox/Events.h virtual key codes (physical ANSI keyboard positions).
    package enum KeyCode: Sendable {
        package static let escape: UInt32 = 53
        package static let delete: UInt32 = 51
        package static let forwardDelete: UInt32 = 117
    }

    package init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    package enum RecordingAction: Equatable, Sendable {
        case combo(HotKeyCombo)
        case requiresModifier
        case cancel
        case clear
    }

    package static func recordingAction(keyCode: UInt32, modifiers: UInt32) -> RecordingAction {
        if keyCode == KeyCode.escape { return .cancel }
        if keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete { return .clear }
        let modifiers = modifiers & Modifier.mask
        guard modifiers != 0 else { return .requiresModifier }
        return .combo(HotKeyCombo(keyCode: keyCode, modifiers: modifiers))
    }
}
