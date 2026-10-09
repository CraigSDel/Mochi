import SwiftUI

struct HardwareRecommendationsView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var store: RecommendationStore
    @ObservedObject var downloads: ModelDownloadCoordinator
    let compact: Bool

    private var result: HardwareRecommendationResult {
        HardwareRecommendationPolicy().evaluate(
            profile: manager.hardwareProfile,
            catalogRecommendations: store.recommendations,
            installedModels: manager.installedModels
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeading(
                    compact ? "Best models for this Mac" : "Best models for this Mac",
                    subtitle: result.message,
                    symbol: "wand.and.stars"
                )
                Spacer()
                if compact {
                    Text("Advisory").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                }
            }
            if result.recommendations.isEmpty {
                Label(result.message, systemImage: manager.hardwareProfile == nil ? "hourglass" : "questionmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(RecommendationRole.allCases, id: \.self) { role in
                    let models = result.recommendations(for: role)
                    if !models.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(role.rawValue).font(.subheadline.weight(.semibold))
                            ForEach(models) { model in
                                HardwareRecommendationRow(model: model, downloads: downloads)
                            }
                        }
                    }
                }
            }
            Text("Recommendations are advisory and never change service settings or selected models.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .appCard(padding: compact ? 14 : 18)
    }
}

private struct HardwareRecommendationRow: View {
    let model: HardwareModelRecommendation
    @ObservedObject var downloads: ModelDownloadCoordinator

    private var catalogModel: ModelRecommendation? { model.catalogRecommendation }
    private var queued: Bool { catalogModel.map(downloads.isQueued) ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.isInstalled ? "checkmark.circle.fill" : "sparkles")
                .foregroundStyle(model.fit == .safe ? .green : .orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(displayName).font(.subheadline.weight(.medium))
                    if model.isInstalled { Text("Installed").font(.caption2.weight(.semibold)).foregroundStyle(.green) }
                    Spacer()
                    Text(model.fit.rawValue).font(.caption).foregroundStyle(model.fit == .safe ? .green : .orange)
                }
                Text("\(model.sizeText) · llama.cpp · \(model.reason)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let catalogModel, !model.isInstalled {
                Button(queued ? "Queued" : "Download") { downloads.enqueue(catalogModel) }
                    .buttonStyle(AppleSecondaryButtonStyle()).disabled(queued)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String { catalogModel?.name ?? model.modelID.replacingOccurrences(of: "llama:", with: "") }
}
