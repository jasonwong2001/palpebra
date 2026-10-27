import PalpebraCore
import SwiftUI

/// Analysis tab: usage duration, fatigue-peak duration and break compliance
/// charts over a selected range and granularity, plus CSV export.
@MainActor
struct AnalysisView: View {
    @ObservedObject var store: UsageStore
    @Binding var range: AnalysisRange
    @Binding var granularity: AnalysisGranularity

    var body: some View {
        let buckets = store.buckets(last: range.rawValue, by: granularity)
        let average = store.dailyAverage(last: range.rawValue)
        VStack(spacing: 0) {
            // One quiet row under the window's tabs: the range as a menu, the granularity beside the charts.
            HStack {
                Picker("Range", selection: $range) {
                    ForEach(AnalysisRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Picker("Granularity", selection: $granularity) {
                    ForEach(AnalysisGranularity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if buckets.isEmpty {
                Spacer()
                Text("No usage recorded yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    // The range's headline number comes first; a year of daily rows would bury it at the end.
                    VStack(alignment: .leading, spacing: 22) {
                        complianceChart(buckets: buckets)
                        chart(
                            title: "Screen time",
                            average: average.activeMinutes,
                            values: buckets.map { ($0.label, $0.activeMinutes) },
                            color: Palette.chartUse
                        )
                        chart(
                            title: "Time at high fatigue (80% or more)",
                            average: average.fatiguedMinutes,
                            values: buckets.map { ($0.label, $0.fatiguedMinutes) },
                            color: Palette.chartHigh
                        )
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private func section<Content: View>(
        _ title: String, detail: (text: String, spoken: String)? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let detail {
                    Text(detail.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(detail.spoken)
                }
            }
            content()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.35)))
        }
    }

    /// A single-series bar chart: bars grow from a square baseline with the value at the tip, in ink.
    /// Rows are built lazily, so a year of days lays out only the rows on screen each time usage updates.
    @ViewBuilder
    private func chart(title: String, average: Double, values: [(String, Double)], color: Color) -> some View {
        let averageMinutes = DisplayNumber.nonnegativeInteger(average)
        section(
            title,
            detail: (
                "Average \(DurationText.minutes(averageMinutes)) a day",
                "Average \(DurationText.spoken(minutes: averageMinutes)) a day"
            )
        ) {
            let maxV = max(1, values.map { $0.1 }.max() ?? 0)
            // Labels are short English dates, so their length sets a column every bar can start from.
            let labelWidth = CGFloat(values.map(\.0.count).max() ?? 0) * 7
            LazyVStack(spacing: 7) {
                ForEach(values.indices, id: \.self) { index in
                    let (label, minutes) = values[index]
                    HStack(spacing: 10) {
                        Text(label)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: labelWidth, alignment: .leading)
                        GeometryReader { geo in
                            // Leaves room past the longest bar for a value such as "12 h 30 min".
                            let barWidth = max(0, (geo.size.width - 76) * CGFloat(minutes / maxV))
                            HStack(spacing: 6) {
                                // Thin marks: a long saturated block reads louder than the minutes it shows.
                                DataBar()
                                    .fill(color)
                                    .frame(width: barWidth, height: 8)
                                Text(DurationText.minutes(minutes))
                                    .font(.caption.monospacedDigit())
                                    .fixedSize()
                                Spacer(minLength: 0)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 16)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title), \(label)")
                    .accessibilityValue(DurationText.spoken(minutes: DisplayNumber.nonnegativeInteger(minutes)))
                }
            }
            .padding(6)
        }
    }

    private func complianceChart(buckets: [Bucket]) -> some View {
        section("Break compliance rate") {
            let summary = BreakSummary(summaries: buckets.map(\.breakSummary))
            let rate = summary.compliance
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Completion rate")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(DisplayNumber.nonnegativeInteger(rate * 100))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                // A magnitude, not a status: the fill is the series color on a lighter step of itself.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.chartUse.opacity(0.18))
                        Capsule()
                            .fill(Palette.chartUse)
                            .frame(width: geo.size.width * CGFloat(rate))
                    }
                }
                .frame(height: 8)
                Text("\(summary.completed) of \(summary.started) breaks completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Skipped: \(summary.skipped) · Ignored: \(summary.ignored) · Emergency: \(summary.emergency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Break compliance")
            .accessibilityValue(
                "\(DisplayNumber.nonnegativeInteger(rate * 100)) percent, \(summary.completed) of \(summary.started) breaks completed. \(summary.skipped) skipped, \(summary.ignored) ignored, \(summary.emergency) emergency."
            )
        }
    }
}

/// A bar that grows from a square baseline to a 4 pt rounded data end.
struct DataBar: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(4, rect.height / 2, rect.width)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
