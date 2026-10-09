import SwiftUI

enum PerformanceSetting: String, CaseIterable, Sendable {
    case context
    case gpuLayers
    case batch
    case microBatch
    case kvKey
    case kvValue
    case cacheReuse
    case flashAttention
    case threads
    case batchThreads
    case maxOutput
    case temperature
    case topK
    case topP
    case repeatPenalty
    case autocompleteLimit
    case presets
}

struct PerformanceSettingHelp: Identifiable, Equatable, Sendable {
    let id: PerformanceSetting
    let title: String
    let tooltip: String
    let explanation: String

    var accessibilityLabel: String { "More information about \(title)" }
}

enum PerformanceSettingHelpCatalog {
    static let all: [PerformanceSettingHelp] = [
        .init(id: .context, title: "Context", tooltip: "Maximum context window in tokens.", explanation: "The maximum number of tokens the model can consider in one request, including the prompt and generated response. Larger contexts help with long files and conversations but use more memory."),
        .init(id: .gpuLayers, title: "GPU layers", tooltip: "How much of the model is placed on the GPU.", explanation: "The number of model layers loaded onto the GPU. Higher values can improve speed, but require more GPU memory. The best value depends on your Mac and model size."),
        .init(id: .batch, title: "Batch", tooltip: "Tokens processed together during evaluation.", explanation: "The number of tokens processed together when evaluating a prompt. Larger batches can improve prompt processing speed, but use more memory."),
        .init(id: .microBatch, title: "Micro-batch", tooltip: "The smaller chunks used inside a batch.", explanation: "Splits a batch into smaller chunks for processing. Larger values can improve throughput, while smaller values reduce peak memory use and may be safer on constrained hardware."),
        .init(id: .kvKey, title: "KV key", tooltip: "Precision used for key attention-cache values.", explanation: "Controls the numeric precision of the key portion of the attention key-value cache. Lower precision saves memory; higher precision may preserve more accuracy."),
        .init(id: .kvValue, title: "KV value", tooltip: "Precision used for value attention-cache values.", explanation: "Controls the numeric precision of the value portion of the attention key-value cache. Lower precision saves memory; higher precision may preserve more accuracy."),
        .init(id: .cacheReuse, title: "Cache reuse", tooltip: "How aggressively prompt cache data is reused.", explanation: "Allows repeated or similar prompts to reuse cached work. Higher values can improve repeated-request latency, but may increase memory pressure."),
        .init(id: .flashAttention, title: "Flash attention", tooltip: "Uses a memory-efficient attention implementation.", explanation: "Enables an optimized attention implementation that can reduce memory use and improve speed on supported hardware. Disable it only if the runtime or model has compatibility problems."),
        .init(id: .threads, title: "Threads", tooltip: "CPU threads used for model inference.", explanation: "The number of CPU threads used for generation. A value of 0 lets the runtime choose automatically. Manually lowering it can leave more CPU available for other work."),
        .init(id: .batchThreads, title: "Batch threads", tooltip: "CPU threads used for prompt processing.", explanation: "The number of CPU threads used when processing batches and prompts. A value of 0 lets the runtime choose automatically. This can be tuned separately from generation threads."),
        .init(id: .maxOutput, title: "Max output", tooltip: "Maximum number of generated tokens.", explanation: "Limits how long a response can be. Higher values allow longer answers but take more time and may use more memory."),
        .init(id: .temperature, title: "Temperature", tooltip: "Controls randomness in generated responses.", explanation: "Higher values make responses more varied and creative. Lower values make them more focused and predictable. Around 0.7 is a general-purpose starting point."),
        .init(id: .topK, title: "Top-k", tooltip: "Limits sampling to the best candidate tokens.", explanation: "Restricts each next-token choice to the top K candidates. Lower values make output more focused; higher values allow more variety. It matters when sampling is enabled."),
        .init(id: .topP, title: "Top-p", tooltip: "Limits sampling to a probability-ranked token set.", explanation: "Chooses from the smallest group of likely tokens whose combined probability reaches this value. Lower values focus the output; higher values allow more variety."),
        .init(id: .repeatPenalty, title: "Repeat penalty", tooltip: "Discourages repeated words and phrases.", explanation: "Penalizes tokens that have already appeared, helping reduce loops and repetitive answers. Values above 1 apply a penalty; values that are too high can make text unnatural."),
        .init(id: .autocompleteLimit, title: "Autocomplete limit", tooltip: "Maximum tokens generated for autocomplete.", explanation: "Caps the length of coding autocomplete results. Lower values keep suggestions fast and concise; higher values allow longer completions."),
        .init(id: .presets, title: "Performance presets", tooltip: "Apply a predefined performance profile.", explanation: "Presets change several related tuning values at once. Fast favors lower memory use and latency, Balanced uses general-purpose values, and Quality favors longer context and output. Applying a preset overwrites those related values for this model assignment.")
    ]

    static func help(for setting: PerformanceSetting) -> PerformanceSettingHelp {
        all.first { $0.id == setting }!
    }
}

struct SettingInfoButton: View {
    let help: PerformanceSettingHelp
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .buttonStyle(.plain)
        .help(help.tooltip)
        .accessibilityLabel(help.accessibilityLabel)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(help.title).font(.headline)
                Text(help.explanation).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
        }
    }
}
