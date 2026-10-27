import CoreGraphics
import Foundation
import IOKit

/// Permission-free time since any keyboard, mouse or trackpad input; no individual events are observed.
@MainActor
enum InputMonitor {
    /// IOHIDSystem lasts as long as the login session, so one lookup serves every sample.
    private static var hidSystem: io_service_t = IO_OBJECT_NULL

    static func idleSeconds() -> Double? {
        if let idle = hidIdleSeconds(), idle.isFinite, idle >= 0 { return idle }
        // The hardware event source exposes the same coarse idle signal without Input Monitoring access.
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        return idle.isFinite && idle >= 0 ? idle : nil
    }

    private static func hidIdleSeconds() -> Double? {
        if hidSystem == IO_OBJECT_NULL {
            hidSystem = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        }
        guard hidSystem != IO_OBJECT_NULL else { return nil }

        guard
            let unmanaged = IORegistryEntryCreateCFProperty(
                hidSystem, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0
            )
        else {
            // A service that stops answering is looked up again on the next sample.
            IOObjectRelease(hidSystem)
            hidSystem = IO_OBJECT_NULL
            return nil
        }
        let value = unmanaged.takeRetainedValue()

        if let number = value as? NSNumber {
            return number.doubleValue / 1_000_000_000
        }
        if let data = value as? Data, data.count == 8 {
            let nanos = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            return Double(UInt64(littleEndian: nanos)) / 1_000_000_000
        }
        return nil
    }
}
