import SwiftUI

struct DownloadableModelSelector: View {
  let title: String
  let options: [ModelOption]
  let selection: String
  let recommendations: [ModelRecommendation]
  @ObservedObject var manager: ServiceManager
  let onSelect: (ModelOption) -> Void
  let onManageDownloads: () -> Void

  private var selectedOption: ModelOption? { options.first { $0.id == selection } }
  private var recommendation: ModelRecommendation? {
    guard let selectedOption, selectedOption.availability != .installed else { return nil }
    return ModelOptionBuilder.recommendation(for: selectedOption, from: recommendations)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ModelSelector(title: title, options: options, selection: selection, onSelect: onSelect)
      if recommendation != nil {
        HStack {
          Text("This model is not installed.").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Manage in Models") { onManageDownloads() }
            .buttonStyle(AppleSecondaryButtonStyle())
        }
      }
    }
  }
}
