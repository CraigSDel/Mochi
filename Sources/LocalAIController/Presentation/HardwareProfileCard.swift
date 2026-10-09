import SwiftUI

struct HardwareProfileCard: View {
    @ObservedObject var manager: ServiceManager

    private var profile: HardwareProfile? { manager.hardwareProfile }
    private var plan: HardwareTuningPlan? { manager.hardwareTuningPlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cpu.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hardware profile").font(.headline)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(manager.isRefreshingHardware ? "Refreshing…" : "Refresh") {
                    Task { await manager.refreshHardwareProfile() }
                }
                .buttonStyle(AppleSecondaryButtonStyle())
                .disabled(manager.isRefreshingHardware)
            }

            if let profile {
                HStack(spacing: 18) {
                    HardwareMetric(title: "Chip", value: profile.chipText)
                    HardwareMetric(title: "Memory", value: profile.memoryText)
                    if !profile.coreText.isEmpty { HardwareMetric(title: "Cores", value: profile.coreText) }
                }
                if !profile.unavailableFields.isEmpty {
                    Label("Unavailable: " + profile.unavailableFields.joined(separator: ", "), systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Measured " + profile.detectedAt.formatted(date: .abbreviated, time: .shortened) + ". Safe tuning changes launch settings only and keeps selected models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Detecting this Mac’s hardware…", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let plan, !plan.notes.isEmpty {
                ForEach(plan.notes, id: \.self) { note in
                    Label(note, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let plan, !plan.modelSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model suggestions").font(.subheadline.weight(.semibold))
                    ForEach(plan.modelSuggestions) { suggestion in
                        Label(suggestion.serviceID.rawValue + ": consider " + suggestion.suggestedModel + " instead of " + suggestion.currentModel, systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Apply safe tuning") { manager.applyHardwareTuning() }
                    .buttonStyle(ApplePrimaryButtonStyle())
                    .disabled(plan?.configurations.isEmpty != false)
                if manager.canRestoreHardwareTuning {
                    Button("Restore previous settings") { manager.restoreHardwareTuning() }
                        .buttonStyle(AppleSecondaryButtonStyle())
                }
                if !manager.hardwareApplyMessage.isEmpty {
                    Text(manager.hardwareApplyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appCard()
    }

    private var summary: String {
        guard let profile else { return "Local hardware detection is in progress." }
        return profile.hasUsefulData ? "Settings sized for this Mac." : "Hardware information could not be read."
    }
}

private struct HardwareMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.subheadline.weight(.medium)).lineLimit(2)
        }
    }
}
