import SwiftUI

struct AdvancedPerformanceTuning: View {
    let gpuLayers: Binding<Int>
    let batchSize: Binding<Int>
    let ubatchSize: Binding<Int>
    let kvKey: Binding<String>
    let kvValue: Binding<String>
    let cacheReuse: Binding<Int>
    let flashAttention: Binding<Bool>
    let threads: Binding<Int>
    let threadsBatch: Binding<Int>
    let generation: Binding<GenerationProfile>?
    let isAutocomplete: Bool

    var body: some View {
        DisclosureGroup("Advanced tuning") {
            VStack(alignment: .leading, spacing: 10) {
                Text("These controls are for fine-tuning a model when you need more control over speed, memory, or sampling.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    field("GPU layers", .gpuLayers) { number("Layers", value: gpuLayers) }
                    field("Batch", .batch) { number("Batch", value: batchSize) }
                    field("Micro-batch", .microBatch) { number("Batch", value: ubatchSize) }
                }
                HStack(spacing: 12) {
                    field("KV key", .kvKey) { TextField("q8_0", text: kvKey).textFieldStyle(.plain).appInputSurface() }
                    field("KV value", .kvValue) { TextField("q8_0", text: kvValue).textFieldStyle(.plain).appInputSurface() }
                    field("Cache reuse", .cacheReuse) { number("Tokens", value: cacheReuse) }
                    HStack(spacing: 4) { Toggle("Flash attention", isOn: flashAttention); SettingInfoButton(help: PerformanceSettingHelpCatalog.help(for: .flashAttention)) }
                }
                HStack(spacing: 12) {
                    field("Threads", .threads) { number("Auto = 0", value: threads) }
                    field("Batch threads", .batchThreads) { number("Auto = 0", value: threadsBatch) }
                }
                if let generation {
                    generationFields(generation, title: isAutocomplete ? "Autocomplete response" : "Chat response")
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
    }

    private func field<Content: View>(_ title: String, _ setting: PerformanceSetting, @ViewBuilder content: () -> Content) -> some View {
        ConfigurationField(title, help: PerformanceSettingHelpCatalog.help(for: setting), content: content)
    }

    private func generationFields(_ binding: Binding<GenerationProfile>, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                field("Max output", .maxOutput) { number("Tokens", value: fieldBinding(binding, \.maximumOutputTokens)) }
                field("Temperature", .temperature) { decimal("0.7", value: fieldBinding(binding, \.temperature)) }
                field("Top-k", .topK) { number("Top-k", value: fieldBinding(binding, \.topK)) }
                field("Top-p", .topP) { decimal("0.9", value: fieldBinding(binding, \.topP)) }
                field("Repeat penalty", .repeatPenalty) { decimal("1.1", value: fieldBinding(binding, \.repeatPenalty)) }
                field("Autocomplete limit", .autocompleteLimit) { number("Tokens", value: fieldBinding(binding, \.autocompleteOutputLimit)) }
            }
        }
    }

    private func fieldBinding<Value>(_ binding: Binding<GenerationProfile>, _ keyPath: WritableKeyPath<GenerationProfile, Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue[keyPath: keyPath] }, set: { binding.wrappedValue[keyPath: keyPath] = $0 })
    }
    private func number(_ title: String, value: Binding<Int>) -> some View { TextField(title, value: value, format: .number).textFieldStyle(.plain).appInputSurface() }
    private func decimal(_ title: String, value: Binding<Double>) -> some View { TextField(title, value: value, format: .number.precision(.fractionLength(2))).textFieldStyle(.plain).appInputSurface() }
}
