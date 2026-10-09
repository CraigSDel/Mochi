import SwiftUI

struct PerformanceGuidanceCard: View {
    let guidance: PerformanceGuidance

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speedometer").font(.title2.weight(.semibold)).foregroundStyle(tone).frame(width: 38, height: 38)
                    .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance guidance · \(guidance.runtime == .ollama ? "Ollama" : "llama.cpp")").font(.headline)
                    Text(guidance.modelLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(guidance.severity.rawValue.capitalized).font(.caption.weight(.semibold)).foregroundStyle(tone)
            }
            Text(guidance.summary).font(.subheadline)
            Text("Advisory only — this guidance does not change launch settings or start services.").font(.caption).foregroundStyle(AppTheme.secondaryText)
            ForEach(guidance.recommendations, id: \.self) { recommendation in
                Label(recommendation, systemImage: recommendation.hasPrefix("MLX/") ? "info.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(recommendation.hasPrefix("MLX/") ? AppTheme.secondaryText : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.appCard()
    }

    private var tone: Color {
        switch guidance.severity { case .safe: .green; case .caution: .orange; case .high: .red; case .unverified: .secondary }
    }
}

struct RecommendationCard: View {
    let model: ModelRecommendation
    let queued: Bool
    let canQueue: Bool
    let onQueue: () -> Void

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
            }.font(.caption2).foregroundStyle(.tertiary)
            if canQueue || queued {
                Button { onQueue() } label: {
                    Label(queued ? "Queued for download" : "Add to download list", systemImage: queued ? "checkmark.circle.fill" : "arrow.down.circle")
                }.buttonStyle(AppleSecondaryButtonStyle()).disabled(queued)
            }
        }.appCard()
    }
}
