import SwiftUI

extension MemoryDashboardView {
  var legend: some View {
    let sample = monitor.currentSample
    return VStack(alignment: .leading, spacing: 6) {
      Text("Latest service readings")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.secondaryText)
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading,
        spacing: 8
      ) {
        legendItem(
          "Total system used", value: sample.map { MemoryFormatting.bytes($0.systemUsedBytes) },
          color: AppTheme.accent)
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

  private func legendItem(_ title: String, value: String?, detail: String? = nil, color: Color)
    -> some View
  {
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

  func color(for id: ServiceID) -> Color {
    switch id {
    case .llamaChat: .purple
    case .autocomplete: .orange
    case .embeddings: .green
    }
  }
}
