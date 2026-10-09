import SwiftUI
import AppKit

struct PerformanceTuningEditor: View {
    let serviceID: ServiceID
    @ObservedObject var manager: ServiceManager
    let assignedRole: RecommendationRole?
    @State private var selectedRole: RecommendationRole = .chat

    init(serviceID: ServiceID, manager: ServiceManager, role: RecommendationRole? = nil) {
        self.serviceID = serviceID; self.manager = manager; self.assignedRole = role
        _selectedRole = State(initialValue: role ?? .chat)
    }

    private var effectiveRole: RecommendationRole { assignedRole ?? (serviceID == .ollama ? selectedRole : manager.modelRole(for: serviceID)) }
    private var profile: ModelSettingsProfile { manager.modelSettings(for: serviceID, role: effectiveRole) }
    private var locked: Bool { manager.isConfigurationLocked(serviceID) }
    private var isAutocomplete: Bool { effectiveRole == .coding }
    private var hasGeneration: Bool { effectiveRole != .embedding }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Model performance and response", subtitle: "These settings belong to the selected model assignment.", symbol: "speedometer")
            HStack(spacing: 8) {
                if serviceID == .ollama && assignedRole == nil {
                    ThemedMenuPicker(choices: RecommendationRole.allCases.map { ($0.rawValue, $0) }, selection: $selectedRole)
                        .frame(width: 190)
                }
                Text("Preset").font(.subheadline.weight(.medium))
                ForEach(PerformancePreset.allCases) { preset in
                    Button(preset.title) { apply(preset) }.buttonStyle(AppleSecondaryButtonStyle())
                }
                Spacer()
                Button("Export providers") { exportProviders() }.buttonStyle(AppleSecondaryButtonStyle())
            }
            if profile.runtime == .llamaCpp { llamaControls } else { ollamaControls }
            Text("Fast lowers memory use and response latency. Quality favors longer context and output, which can increase memory pressure and time to first token.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(locked)
        .appCard()
    }

    private var llamaControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ConfigurationField("Context") { number("Tokens", value: llamaBinding(\.contextSize)) }
                ConfigurationField("GPU layers") { number("Layers", value: llamaBinding(\.gpuLayers)) }
                ConfigurationField("Batch") { number("Batch", value: llamaBinding(\.batchSize)) }
                ConfigurationField("Micro-batch") { number("Batch", value: llamaBinding(\.ubatchSize)) }
            }
            HStack(spacing: 12) {
                ConfigurationField("KV key") { TextField("q8_0", text: llamaBinding(\.kvCacheKeyType)).textFieldStyle(.plain).appInputSurface() }
                ConfigurationField("KV value") { TextField("q8_0", text: llamaBinding(\.kvCacheValueType)).textFieldStyle(.plain).appInputSurface() }
                ConfigurationField("Cache reuse") { number("Tokens", value: llamaBinding(\.cacheReuse)) }
                Toggle("Flash attention", isOn: llamaBinding(\.flashAttention))
            }
            HStack(spacing: 12) {
                ConfigurationField("Threads") { number("Auto = 0", value: llamaBinding(\.threads)) }
                ConfigurationField("Batch threads") { number("Auto = 0", value: llamaBinding(\.threadsBatch)) }
            }
            if hasGeneration { generationFields(llamaBinding(\.generation), title: isAutocomplete ? "Autocomplete response" : "Chat response") }
        }
    }

    private var ollamaControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generation settings for this Ollama model").font(.subheadline.weight(.semibold))
            if hasGeneration { generationFields(ollamaBinding(\.generation), title: isAutocomplete ? "Autocomplete response" : "Chat response") }
            if !hasGeneration { Text("Embedding models do not use generation settings.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func generationFields(_ binding: Binding<GenerationProfile>, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                ConfigurationField("Max output") { number("Tokens", value: field(binding, \.maximumOutputTokens)) }
                ConfigurationField("Temperature") { decimal("0.7", value: field(binding, \.temperature)) }
                ConfigurationField("Top-k") { number("Top-k", value: field(binding, \.topK)) }
                ConfigurationField("Top-p") { decimal("0.9", value: field(binding, \.topP)) }
                ConfigurationField("Repeat penalty") { decimal("1.1", value: field(binding, \.repeatPenalty)) }
                ConfigurationField("Autocomplete limit") { number("Tokens", value: field(binding, \.autocompleteOutputLimit)) }
            }
        }
    }

    private func apply(_ preset: PerformancePreset) {
        var copy = profile
        if let llama = copy.llama {
            let baseline = ModelSettingsProfile.defaults(runtime: .llamaCpp, role: copy.role).llama?.contextSize
            copy.llama = PerformancePresetMapper.llama(llama, preset: preset, baselineContext: baseline)
        }
        if copy.ollama != nil {
            switch preset {
            case .fast: copy.ollama?.generation = .init(maximumOutputTokens: 512, temperature: 0.7, topK: 32, topP: 0.9, repeatPenalty: 1.1, autocompleteOutputLimit: 128)
            case .balanced: copy.ollama?.generation = copy.role == .coding ? .autocompleteBalanced : .balanced
            case .quality: copy.ollama?.generation = .init(maximumOutputTokens: 2_048, temperature: 0.7, topK: 80, topP: 0.95, repeatPenalty: 1.05, autocompleteOutputLimit: 512)
            }
        }
        manager.updateModelSettings(copy, for: serviceID, role: effectiveRole)
    }

    private func exportProviders() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "twinny-providers.json"; panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ProviderExportBuilder.data(configurations: manager.configurations, modelSettings: manager.modelSettings).write(to: url, options: .atomic) } catch { NSSound.beep() }
    }

    private func llamaBinding<Value>(_ keyPath: WritableKeyPath<LlamaModelSettings, Value>) -> Binding<Value> {
        Binding(get: { profile.llama![keyPath: keyPath] }, set: { value in var copy = profile; copy.llama![keyPath: keyPath] = value; manager.updateModelSettings(copy, for: serviceID, role: effectiveRole) })
    }
    private func ollamaBinding<Value>(_ keyPath: WritableKeyPath<OllamaModelSettings, Value>) -> Binding<Value> {
        Binding(get: { profile.ollama![keyPath: keyPath] }, set: { value in var copy = profile; copy.ollama![keyPath: keyPath] = value; manager.updateModelSettings(copy, for: serviceID, role: effectiveRole) })
    }
    private func field<Value>(_ binding: Binding<GenerationProfile>, _ keyPath: WritableKeyPath<GenerationProfile, Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue[keyPath: keyPath] }, set: { binding.wrappedValue[keyPath: keyPath] = $0 })
    }
    private func number(_ title: String, value: Binding<Int>) -> some View { TextField(title, value: value, format: .number).textFieldStyle(.plain).appInputSurface() }
    private func decimal(_ title: String, value: Binding<Double>) -> some View { TextField(title, value: value, format: .number.precision(.fractionLength(2))).textFieldStyle(.plain).appInputSurface() }
}
