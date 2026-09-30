import SwiftUI

struct RecommendationsView: View {
    @ObservedObject var store: RecommendationStore
    @State private var role: RecommendationRole?
    @AppStorage("recommendations.compatibilityFilter") private var compatibilityFilter: RecommendationCompatibilityFilter = .all
    var filtered: [ModelRecommendation] { compatibilityFilter.apply(to: store.recommendations, role: role) }
    private var hasFailure: Bool { store.status.hasPrefix("Unavailable") }
    private var hasActiveFilter: Bool { role != nil || compatibilityFilter != .all }

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
                    .buttonStyle(ApplePrimaryButtonStyle())
                    .disabled(store.isRefreshing)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Role")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                        HStack(spacing: 4) {
                            roleButton("All roles", value: nil)
                            ForEach(RecommendationRole.allCases, id: \.self) { item in
                                roleButton(item.rawValue, value: item)
                            }
                        }
                        .padding(4)
                        .background(AppTheme.pageBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    HStack(spacing: 12) {
                        Text("Compatibility")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                        HStack(spacing: 4) {
                            compatibilityButton("All", value: .all)
                            compatibilityButton("Compatible only", value: .compatibleOnly)
                        }
                        .padding(4)
                        .background(AppTheme.pageBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
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
                        title: hasFailure ? "Recommendations unavailable" : (hasActiveFilter && !store.recommendations.isEmpty ? "No matching recommendations" : "No recommendations yet"),
                        message: hasFailure ? "Check your connection and try again. Cached results will remain available." : (hasActiveFilter && !store.recommendations.isEmpty ? "Change the role or compatibility filter to see more models." : "Check the registries now to find models that fit this Mac.")
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { model in RecommendationCard(model: model) }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
        }
        .background(AppTheme.pageBackground)
    }

    private func roleButton(_ title: String, value: RecommendationRole?) -> some View {
        let selected = role == value
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { role = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.white : AppTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func compatibilityButton(_ title: String, value: RecommendationCompatibilityFilter) -> some View {
        let selected = compatibilityFilter == value
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { compatibilityFilter = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.white : AppTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityAddTraits(selected ? .isSelected : [])
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
