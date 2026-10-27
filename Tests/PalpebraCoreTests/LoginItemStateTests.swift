import Foundation
import PalpebraCore
import Testing

struct LoginItemStateTests {
    @Test func onlyEnabledSystemStatusTurnsTheToggleOn() throws {
        // A legacy preference must not override the current system status.
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"launchAtLogin":true}"#.utf8))
        #expect(legacy.launchAtLogin)
        for status in [LoginItemState.notRegistered, .requiresApproval, .unavailable] {
            #expect(!status.isEnabled)
        }
        #expect(LoginItemState.enabled.isEnabled)
        #expect(LoginItemState.requiresApproval.approvalHint != nil)
        #expect(LoginItemState.enabled.approvalHint == nil)
        #expect(LoginItemState.notRegistered.approvalHint == nil)
    }
}
