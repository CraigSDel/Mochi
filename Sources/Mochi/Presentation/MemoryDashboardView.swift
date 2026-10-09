import SwiftUI
import Charts

struct MemoryDashboardView: View {
    @ObservedObject var monitor: MemoryMonitor
    @State private var selectedTimestamp: Date?

    private var selectedSample: MemorySample? {
        guard let selectedTimestamp else { return nil }
        return monitor.samples.min {
            abs($0.timestamp.timeIntervalSince(selectedTimestamp)) <
                abs($1.timestamp.timeIntervalSince(selectedTimestamp))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(
                    "Live memory",
                    subtitle: "A 15-minute view of total system usage and its measured composition.",
                    symbol: "memorychip"
                )
                if let sample = monitor.currentSample {
                    HStack(spacing: 20) {
                        metric("Latest system", MemoryFormatting.usage(sample.systemUsedBytes, of: sample.systemTotalBytes))
                        metric("Latest managed AI", MemoryFormatting.managedUsage(sample))
                        metric("Other usage", MemoryFormatting.bytes(sample.otherSystemUsageBytes))
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        Text("Latest sample")
                        Text(sample.timestamp, format: .dateTime.hour().minute().second())
                    }
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)

                    if let selectedSample, selectedSample.id != sample.id {
                        HStack(spacing: 20) {
                            metric("Selected system", MemoryFormatting.usage(selectedSample.systemUsedBytes, of: selectedSample.systemTotalBytes))
                            metric("Selected managed AI", MemoryFormatting.managedUsage(selectedSample))
                            metric("Selected other", MemoryFormatting.bytes(selectedSample.otherSystemUsageBytes))
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 6) {
                            Text("Historical sample")
                            Text(selectedSample.timestamp, format: .dateTime.hour().minute().second())
                        }
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

            if monitor.samples.isEmpty {
                FriendlyEmptyState(
                    symbol: "chart.xyaxis.line",
                    title: "Waiting for memory data",
                    message: "The timeline will appear as soon as a system reading is available."
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                charts
                legend
            }
        }
        .appCard()
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System memory usage")
                .font(.subheadline.weight(.semibold))
            memoryChart
                .frame(height: 220)

            Text("Service footprints are included in total system usage. Other system usage represents macOS, background applications, caches, and untracked processes not attributed to controller-owned process trees.")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            if monitor.currentSample?.readingsMayBeIncomplete == true {
                Label("Some service footprints are unavailable; readings may be incomplete.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var memoryChart: some View {
        let samples = monitor.samples
        let timeline = MemoryChartTimeline.samples(from: samples, maximumGap: .infinity)
        let scale = MemoryChartScale(samples: samples)
        return Chart {
            ForEach(timeline) { chartSample in
                ForEach(chartSample.segments.filter(\.isMeasured)) { segment in
                    LineMark(
                        x: .value("Time", chartSample.timestamp),
                        y: .value("Memory", scale.value(for: segment.bytes)),
                        series: .value("Memory source", segment.id)
                    )
                    .foregroundStyle(segment.serviceID.map(color(for:)) ?? .gray)
                    .lineStyle(.init(lineWidth: 1.5))
                }
            }
            ForEach(timeline) { chartSample in
                LineMark(
                    x: .value("Time", chartSample.timestamp),
                    y: .value("Total system used", scale.value(for: chartSample.totalSystemUsedBytes)),
                    series: .value("Memory source", "total")
                )
                .foregroundStyle(AppTheme.accent)
                .lineStyle(.init(lineWidth: 2))
            }
            latestRule
            selectionRule
        }
        .chartXScale(domain: timeRange)
        .chartYScale(domain: 0...scale.upperBound)
        .chartYAxisLabel(scale.unit)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.35))
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis { yAxis }
        .chartOverlay { proxy in selectionOverlay(proxy) }
        .accessibilityLabel("System memory usage over the last 15 minutes")
    }

    @ChartContentBuilder
    private var latestRule: some ChartContent {
        if let sample = monitor.currentSample {
            RuleMark(x: .value("Latest", sample.timestamp))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.45))
                .lineStyle(.init(lineWidth: 1))
        }
    }

    @ChartContentBuilder
    private var selectionRule: some ChartContent {
        if let sample = selectedSample {
            RuleMark(x: .value("Selected", sample.timestamp))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.35))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(number, format: .number.precision(.fractionLength(0...1)))
                }
            }
        }
    }

    private func selectionOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        selectedTimestamp = proxy.value(atX: location.x - frame.origin.x)
                    case .ended:
                        selectedTimestamp = nil
                    }
                }
        }
    }

    private var timeRange: ClosedRange<Date> {
        let end = monitor.currentSample?.timestamp ?? .now
        return end.addingTimeInterval(-15 * 60)...end
    }

    private var legend: some View {
        let sample = monitor.currentSample
        return VStack(alignment: .leading, spacing: 6) {
            Text("Latest service readings")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                legendItem("Total system used", value: sample.map { MemoryFormatting.bytes($0.systemUsedBytes) }, color: AppTheme.accent)
                if let sample {
                    ForEach(ServiceID.allCases) { id in
                        let reading = sample.serviceReadings[id]
                        legendItem(
                            MemoryPresentation.label(for: id),
                            value: reading.map(MemoryFormatting.serviceReading),
                            detail: reading.map(MemoryFormatting.serviceReadingDetail),
                            color: color(for: id)
                        )
                    }
                    legendItem(
                        "Other system usage",
                        value: MemoryFormatting.bytes(sample.otherSystemUsageBytes),
                        detail: "macOS, background applications, caches, and untracked processes.",
                        color: .gray
                    )
                }
            }
        }
        .font(.caption)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .padding(.leading, 20)
    }

    private func legendItem(_ title: String, value: String?, detail: String? = nil, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).lineLimit(1).truncationMode(.tail)
            if let value {
                Text(value)
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help(detail ?? value)
            }
        }
    }

    private func color(for id: ServiceID) -> Color {
        switch id {
        case .llamaChat: .purple
        case .autocomplete: .orange
        case .embeddings: .green
        }
    }
}
