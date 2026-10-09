import SwiftUI

struct DownloadManagerSection: View {
  @ObservedObject var downloads: ModelDownloadCoordinator

  var body: some View {
    if downloads.active != nil || !downloads.queued.isEmpty || !downloads.failures.isEmpty
      || !downloads.completed.isEmpty
    {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeading(
          "Downloads",
          subtitle: "Downloads run one at a time and remain available while you navigate.",
          symbol: "arrow.down.circle")
        if let active = downloads.active {
          HStack(spacing: 10) {
            if let fraction = active.progress.fractionCompleted {
              ProgressView(value: fraction).frame(width: 180)
            } else {
              ProgressView().frame(width: 180)
            }
            Text(active.progress.fractionCompleted.map { "\(Int($0 * 100))%" } ?? "Downloading…")
              .font(.caption.monospacedDigit())
            Text(active.recommendation.name).font(.caption).lineLimit(1)
            Spacer()
            Button("Cancel") { downloads.cancelActive() }.buttonStyle(AppleSecondaryButtonStyle())
          }
        }
        ForEach(downloads.queued) { model in
          HStack {
            Image(systemName: "clock")
            Text(model.name).font(.caption)
            Spacer()
            Button("Remove") { downloads.remove(model) }.buttonStyle(AppleSecondaryButtonStyle())
          }
        }
        ForEach(downloads.failures) { failure in
          HStack(alignment: .top) {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(
              .red)
            Spacer()
            Button("Retry") { downloads.retry(failure) }.buttonStyle(AppleSecondaryButtonStyle())
          }
          .font(.caption)
        }
        ForEach(downloads.completed) { model in
          HStack {
            Label("Downloaded \(model.name)", systemImage: "checkmark.circle.fill").foregroundStyle(
              .green)
            Spacer()
            Button("Dismiss") { downloads.dismissCompleted(model) }.buttonStyle(
              AppleSecondaryButtonStyle())
          }
          .font(.caption)
        }
      }
      .appCard(padding: 14)
    }
  }
}
