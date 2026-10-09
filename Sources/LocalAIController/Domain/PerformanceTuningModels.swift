import Foundation

struct GenerationProfile: Codable, Equatable, Sendable {
    var maximumOutputTokens: Int
    var temperature: Double
    var topK: Int
    var topP: Double
    var repeatPenalty: Double
    var autocompleteOutputLimit: Int

    static let balanced = Self(maximumOutputTokens: 1_024, temperature: 0.7, topK: 40, topP: 0.9, repeatPenalty: 1.1, autocompleteOutputLimit: 256)
    static let autocompleteBalanced = Self(maximumOutputTokens: 256, temperature: 0.2, topK: 40, topP: 0.95, repeatPenalty: 1.05, autocompleteOutputLimit: 128)
}

enum PerformancePreset: String, CaseIterable, Identifiable, Sendable {
    case fast, balanced, quality
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PerformancePresetMapper {
    static func llama(_ base: LlamaModelSettings, preset: PerformancePreset, baselineContext: Int? = nil) -> LlamaModelSettings {
        var result = base
        let baseline = baselineContext ?? base.contextSize
        switch preset {
        case .fast:
            result.contextSize = max(4_096, baseline / 2); result.cacheReuse = 128
            result.batchSize = 256; result.ubatchSize = 128
            result.generation = .init(maximumOutputTokens: 512, temperature: 0.7, topK: 32, topP: 0.9, repeatPenalty: 1.1, autocompleteOutputLimit: 128)
        case .balanced:
            result.contextSize = baseline; result.flashAttention = true; result.cacheReuse = 256; result.batchSize = 512; result.ubatchSize = 256
            result.generation = .balanced
        case .quality:
            result.contextSize = min(262_144, baseline * 2); result.cacheReuse = 512
            result.batchSize = 1_024; result.ubatchSize = 512
            result.generation = .init(maximumOutputTokens: 2_048, temperature: 0.7, topK: 80, topP: 0.95, repeatPenalty: 1.05, autocompleteOutputLimit: 512)
        }
        return result
    }

    static func llama(_ base: LlamaLaunchConfiguration, preset: PerformancePreset, baselineContext: Int? = nil) -> LlamaLaunchConfiguration {
        var result = base
        let baseline = baselineContext ?? base.contextSize
        switch preset {
        case .fast:
            result.contextSize = max(4_096, baseline / 2); result.cacheReuse = 128
            result.batchSize = 256; result.ubatchSize = 128
            result.generation = .init(maximumOutputTokens: 512, temperature: 0.7, topK: 32, topP: 0.9, repeatPenalty: 1.1, autocompleteOutputLimit: 128)
        case .balanced:
            result.contextSize = baseline; result.flashAttention = true; result.cacheReuse = 256; result.batchSize = 512; result.ubatchSize = 256
            result.generation = .balanced
        case .quality:
            result.contextSize = min(262_144, baseline * 2); result.cacheReuse = 512
            result.batchSize = 1_024; result.ubatchSize = 512
            result.generation = .init(maximumOutputTokens: 2_048, temperature: 0.7, topK: 80, topP: 0.95, repeatPenalty: 1.05, autocompleteOutputLimit: 512)
        }
        return result
    }

    static func ollama(_ base: OllamaLaunchConfiguration, preset: PerformancePreset) -> OllamaLaunchConfiguration {
        var result = base
        switch preset {
        case .fast:
            result.contextLength = 8_192; result.parallelRequests = 1; result.maxLoadedModels = 1
            result.chatGeneration = .init(maximumOutputTokens: 512, temperature: 0.7, topK: 32, topP: 0.9, repeatPenalty: 1.1, autocompleteOutputLimit: 128)
            result.autocompleteGeneration = .autocompleteBalanced
        case .balanced:
            result.contextLength = 16_384; result.flashAttention = true; result.parallelRequests = 2; result.maxLoadedModels = 1
            result.chatGeneration = .balanced; result.autocompleteGeneration = .autocompleteBalanced
        case .quality:
            result.contextLength = 32_768; result.parallelRequests = 4; result.maxLoadedModels = 2
            result.chatGeneration = .init(maximumOutputTokens: 2_048, temperature: 0.7, topK: 80, topP: 0.95, repeatPenalty: 1.05, autocompleteOutputLimit: 512)
            result.autocompleteGeneration = .init(maximumOutputTokens: 512, temperature: 0.2, topK: 40, topP: 0.95, repeatPenalty: 1.05, autocompleteOutputLimit: 256)
        }
        return result
    }
}
