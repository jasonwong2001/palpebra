import AppKit
import PalpebraCore
import ServiceManagement
import SwiftUI

/// Settings tab: popup appearance, status indicators, shortcuts, system
/// integration and data management.
@MainActor
struct SettingsTabView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: UsageStore
    @ObservedObject var customBackground = CustomBackground.shared
    @State private var actionError: ActionError?
    @State private var confirmingClear = false
    @State private var loginState: LoginItemState = .notRegistered

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(
                    "Full-screen background",
                    selection: $settings.settings.popupBackground
                ) {
                    ForEach(PopupBackground.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if settings.settings.popupBackground == .custom {
                    HStack {
                        Button("Select Image…") { pickImage() }
                        Button("Remove") {
                            Task {
                                do {
                                    try await customBackground.remove()
                                } catch {
                                    report("Couldn’t remove the image", error: error)
                                }
                            }
                        }
                        if let image = customBackground.image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                NumberField(
                    title: "Full-screen brightness",
                    value: Binding(
                        get: { Int((settings.settings.overlayOpacity * 100).rounded()) },
                        set: { settings.settings.overlayOpacity = Double($0) / 100 }),
                    range: SettingLimits.overlayBrightnessPercent, step: 5, unit: "%")
                Picker(
                    "Mini popup background",
                    selection: $settings.settings.miniBackground
                ) {
                    ForEach(PopupBackground.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                LabeledContent("Full-screen message") {
                    TextField(
                        "Full-screen message",
                        text: $settings.settings.overlayText,
                        prompt: Text("Rest your eyes")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                }
                Toggle(
                    "Play a sound when a break ends",
                    isOn: $settings.settings.breakEndSound)
            }

            Section("Menu bar") {
                Toggle(
                    "Show fatigue percentage",
                    isOn: $settings.settings.statusShowsFatigue)
                Toggle(
                    "Show screen time hours",
                    isOn: $settings.settings.statusShowsHours)
                Toggle(
                    "Show screen time minutes",
                    isOn: $settings.settings.statusShowsMinutes)
            }

            Section("Dock") {
                Toggle(
                    "Show Palpebra in the Dock",
                    isOn: $settings.settings.showDockIcon)
                FormNote("The Dock icon shows your fatigue as a ring.")
            }

            Section("Shortcut") {
                LabeledContent("Rest now") {
                    HotKeyRecorder(
                        combo: $settings.settings.restHotkey,
                        onRecordingChanged: { settings.isRecordingHotkey = $0 }
                    )
                    // SwiftUI doesn't read an AppKit view's baseline; align on the centered text's baseline.
                    .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 4.4 }
                }
                if let error = settings.hotkeyRegistrationError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                FormNote("Works from any app. Click the shortcut and press Delete to remove it.")
            }

            Section("System") {
                Toggle(
                    "Open at login",
                    isOn: Binding(get: { loginState.isEnabled }, set: { setLoginItem(enabled: $0) })
                )
                .disabled(loginState == .unavailable)
                if let hint = loginState.approvalHint {
                    Text(hint).font(.footnote).foregroundStyle(.orange)
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                if loginState == .unavailable {
                    Text("Available in the installed app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("History") {
                Button("Export as CSV…") {
                    exportCSV()
                }
                Button("Clear History…", role: .destructive) {
                    confirmingClear = true
                }
                FormNote("Your history stays on this Mac.")
            }

            Section("About") {
                Text(
                    AppVersion.label(
                        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                        + " · Open source under the MIT License"
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .alert(
            Text(actionError?.title ?? ""),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError?.detail ?? "")
        }
        .onAppear { refreshLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItem()
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A large photo takes a moment to decode off the main thread; its thumbnail appears when it's ready.
        Task {
            do {
                try await customBackground.adopt(url)
            } catch {
                report("Couldn’t use that image", error: error)
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "palpebra-usage.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            report("Couldn’t export your history", error: error)
        }
    }

    private func clearHistory() {
        do {
            try store.clear()
        } catch {
            report("Couldn’t clear your history", error: error)
        }
    }

    /// An alert leads with what went wrong; the system's explanation goes underneath.
    private struct ActionError: Equatable {
        let title: String
        let detail: String
    }

    private func report(_ title: String, error: Error) {
        AppLog.actions.error("\(title, privacy: .public): \(error)")
        actionError = ActionError(title: title, detail: error.localizedDescription)
    }

    private func refreshLoginItem() {
        guard Bundle.main.bundleURL.pathExtension == "app", !AppEnvironment.current.isDevelopment else {
            loginState = .unavailable
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled: loginState = .enabled
        case .requiresApproval: loginState = .requiresApproval
        case .notRegistered: loginState = .notRegistered
        case .notFound: loginState = .unavailable
        @unknown default: loginState = .unavailable
        }
    }

    private func setLoginItem(enabled: Bool) {
        defer { refreshLoginItem() }
        guard Bundle.main.bundleURL.pathExtension == "app", !AppEnvironment.current.isDevelopment else {
            actionError = ActionError(
                title: "Open at login isn’t available", detail: "It works in the installed app.")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            report("Couldn’t change Open at login", error: error)
        }
    }
}
