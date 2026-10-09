import SwiftUI
import AppKit

struct PerformanceTuningEditor: View {
    let serviceID: ServiceID
    @ObservedObject var manager: ServiceManager
    let assignedRole: RecommendationRole?

    init(serviceID: ServiceID, manager: ServiceManager, role: RecommendationRole? = nil) {
        self.serviceID = serviceID; self.manager = manager; self.assignedRole = role
    }

    private var effectiveRole: RecommendationRole { assignedRole ?? manager.modelRole(for: serviceID) }
    private var profile: ModelSettingsProfile { manager.modelSettings(for: serviceID, role: effectiveRole) }
    private var locked: Bool { manager.isConfigurationLocked(serviceID) }
    private var hasGeneration: Bool { effectiveRole != .embedding }
    private var baselineContext: Int? { ModelSettingsProfile.defaults(runtime: .llamaCpp, role: profile.role).llama?.contextSize }
    private var activeProfile: BeginnerPerformanceProfile {
        PerformanceTuningPresentation.activeProfile(for: profile.llama, role: effectiveRole, baselineContext: baselineContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Model performance and response", subtitle: "Choose a simple recommendation, then fine-tune only if you need to.", symbol: "speedometer")
            recommendationCards
            if profile.llama != nil {
                BeginnerPerformanceControls(
                    context: llamaBinding(\.contextSize),
                    generation: hasGeneration ? llamaGenerationBinding : nil,
                    role: effectiveRole,
                    assessment: manager.memoryAssessment(for: serviceID)
                )
                AdvancedPerformanceTuning(
                    gpuLayers: llamaBinding(\.gpuLayers), batchSize: llamaBinding(\.batchSize), ubatchSize: llamaBinding(\.ubatchSize),
                    kvKey: llamaTextBinding(\.kvCacheKeyType), kvValue: llamaTextBinding(\.kvCacheValueType), cacheReuse: llamaBinding(\.cacheReuse),
                    flashAttention: llamaBoolBinding(\.flashAttention), threads: llamaBinding(\.threads), threadsBatch: llamaBinding(\.threadsBatch),
                    generation: hasGeneration ? llamaGenerationBinding : nil, isAutocomplete: effectiveRole == .coding
                )
            }
            HStack {
                Text("Profile: \(activeProfile.title)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Export providers") { exportProviders() }.buttonStyle(AppleSecondaryButtonStyle())
            }
        }
        .disabled(locked)
        .appCard()
    }

    private var recommendationCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Recommendations").font(.subheadline.weight(.semibold))
                SettingInfoButton(help: PerformanceSettingHelpCatalog.help(for: .presets))
            }
            HStack(spacing: 8) {
                ForEach(BeginnerPerformanceProfile.allCases) { option in
                    PerformanceRecommendationCard(option: option, selected: activeProfile == option) { apply(option.preset) }
                }
            }
        }
    }

    private var llamaGenerationBinding: Binding<GenerationProfile> {
        Binding(get: { profile.llama!.generation }, set: { value in update { $0.generation = value } })
    }

    private func apply(_ preset: PerformancePreset) {
        guard let current = profile.llama else { return }
        var copy = profile; copy.llama = PerformancePresetMapper.llama(current, preset: preset, baselineContext: baselineContext)
        manager.updateModelSettings(copy, for: serviceID, role: effectiveRole)
    }

    private func update(_ change: (inout LlamaModelSettings) -> Void) {
        guard var llama = profile.llama else { return }; change(&llama)
        var copy = profile; copy.llama = llama
        manager.updateModelSettings(copy, for: serviceID, role: effectiveRole)
    }

    private func llamaBinding<Value>(_ keyPath: WritableKeyPath<LlamaModelSettings, Value>) -> Binding<Value> {
        Binding(get: { profile.llama![keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }
    private func llamaTextBinding(_ keyPath: WritableKeyPath<LlamaModelSettings, String>) -> Binding<String> { llamaBinding(keyPath) }
    private func llamaBoolBinding(_ keyPath: WritableKeyPath<LlamaModelSettings, Bool>) -> Binding<Bool> { llamaBinding(keyPath) }

    private func exportProviders() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "twinny-providers.json"; panel.canCreateDirectories = true; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ProviderExportBuilder.data(configurations: manager.configurations, modelSettings: manager.modelSettings).write(to: url, options: .atomic) } catch { NSSound.beep() }
    }
}

private struct PerformanceRecommendationCard: View {
    let option: BeginnerPerformanceProfile
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(option.cardTitle).font(.subheadline.weight(.semibold))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill") }
                }
                Text(option.summary).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(10)
            .background(selected ? AppTheme.accent.opacity(0.12) : AppTheme.pageBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? AppTheme.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain).foregroundStyle(AppTheme.primaryText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
