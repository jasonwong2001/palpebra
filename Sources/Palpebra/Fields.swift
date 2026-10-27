import PalpebraCore
import SwiftUI

/// Help lives inside its section so it can use the full row width before wrapping.
@MainActor
struct FormNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A whole number you can type or step, with its unit. Typed values are clamped to the setting's
/// range when you press Return or leave the field; the range shows as a tooltip.
@MainActor
struct NumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 52)
                    .focused($focused)
                    .onSubmit(commit)
                // Steps from what's typed, even before Return.
                Stepper(
                    title,
                    onIncrement: { nudge(by: step) },
                    onDecrement: { nudge(by: -step) }
                )
                .labelsHidden()
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            .help("\(range.lowerBound)–\(range.upperBound) \(unit)")
        }
        .onAppear { text = String(value) }
        // Switching tabs removes the field without ending its focus, so apply what's typed.
        .onDisappear(perform: commit)
        .onChange(of: value) { text = String($0) }
        .onChange(of: focused) { if !$0 { commit() } }
    }

    private func nudge(by delta: Int) {
        commit()
        value = SettingLimits.clamp(value + delta, to: range)
    }

    private func commit() {
        if let typed = Int(text.trimmingCharacters(in: .whitespaces)) {
            value = SettingLimits.clamp(typed, to: range)
        }
        text = String(value)
    }
}

/// A duration typed as a number plus a seconds/minutes menu, as in Calendar's custom alerts, so a
/// 20-second break is as easy to enter as a 5-minute one.
@MainActor
struct DurationField: View {
    let title: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>

    @State private var text = ""
    @State private var unit = DurationUnit.minutes
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 52)
                    .focused($focused)
                    .onSubmit(commit)
                Stepper(
                    title,
                    onIncrement: { nudge(by: 1) },
                    onDecrement: { nudge(by: -1) }
                )
                .labelsHidden()
                // A quiet unit menu, so it reads as the unit rather than a second control.
                Picker("\(title) unit", selection: $unit) {
                    ForEach(DurationUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .labelsHidden()
                .fixedSize()
                .tint(.primary)
            }
            .help(
                "\(DurationParts(seconds: range.lowerBound).text) to \(DurationParts(seconds: range.upperBound).text)")
        }
        .onAppear(perform: showValue)
        .onDisappear(perform: commit)
        .onChange(of: seconds) { _ in showValue() }
        // Changing the unit keeps the number, like Calendar: "5 sec" becomes "5 min".
        .onChange(of: unit) { _ in commit() }
        .onChange(of: focused) { if !$0 { commit() } }
    }

    private func nudge(by direction: Int) {
        commit()
        seconds = DurationParts.nudged(seconds, by: direction, within: range)
    }

    private func showValue() {
        let parts = DurationParts(seconds: seconds)
        text = String(parts.value)
        unit = parts.unit
    }

    private func commit() {
        if let typed = Int(text.trimmingCharacters(in: .whitespaces)) {
            seconds = DurationParts.seconds(typed: typed, unit, within: range)
        }
        showValue()
    }
}

extension DurationParts {
    fileprivate var text: String { "\(value) \(unit.label)" }
}
