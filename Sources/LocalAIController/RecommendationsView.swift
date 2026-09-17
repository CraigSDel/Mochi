import SwiftUI

struct RecommendationsView: View {
    @ObservedObject var store: RecommendationStore
    @State private var role: RecommendationRole?
    var filtered: [ModelRecommendation] { role.map { wanted in store.recommendations.filter { $0.role == wanted } } ?? store.recommendations }
    private var hasFailure: Bool { store.status.hasPrefix("Unavailable") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PageHeader(
                        eyebrow: "Discover",
                        title: "Model recommendations",
                        subtitle: "Conservative suggestions sized for local use on this Mac.",
                        symbol: "sparkles"
                    )
                    Spacer()
                    Button { Task { await store.refresh() } } label: {
                        if store.isRefreshing {
                            HStack { ProgressView().controlSize(.small); Text("Checking…") }
                        } else {
                            Label("Check Now", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isRefreshing)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Role", selection: $role) {
                        Text("All roles").tag(nil as RecommendationRole?)
                        ForEach(RecommendationRole.allCases, id: \.self) { Text($0.rawValue).tag($0 as RecommendationRole?) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Image(systemName: hasFailure ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                            .foregroundStyle(hasFailure ? Color.orange : AppTheme.accent)
                        Text(store.status)
                        Spacer()
                        if let lastChecked = store.lastChecked {
                            Text("Updated \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .appCard(padding: 14)

                if filtered.isEmpty && !store.isRefreshing {
                    FriendlyEmptyState(
                        symbol: hasFailure ? "wifi.exclamationmark" : "sparkles",
                        title: hasFailure ? "Recommendations unavailable" : "No recommendations yet",
                        message: hasFailure ? "Check your connection and try again. Cached results will remain available." : "Check the registries now to find models that fit this Mac."
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { model in RecommendationCard(model: model) }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RecommendationCard: View {
    let model: ModelRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name).font(.headline).textSelection(.enabled)
                    Label(model.source, systemImage: "building.columns").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                CompatibilityBadge(compatibility: model.compatibility)
            }
            HStack(spacing: 24) {
                MetadataLabel(title: "Role", value: model.role.rawValue, symbol: "person.crop.circle")
                MetadataLabel(title: "Runtime", value: model.runtime, symbol: "gearshape.2")
                MetadataLabel(title: "Format", value: model.quantization, symbol: "cube")
                MetadataLabel(title: "Size", value: model.sizeText, symbol: "internaldrive")
                Spacer()
            }
            Text(model.rationale).font(.subheadline).foregroundStyle(.secondary)
            Divider()
            HStack {
                Label("License: \(model.license)", systemImage: "doc.text")
                Spacer()
                Text("Updated \(model.updatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "unknown")")
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
        .appCard()
    }
}

