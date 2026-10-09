import Foundation

struct ModelAssignmentKey: Codable, Equatable, Hashable, Sendable {
    let runtime: ModelRuntime
    let modelID: String
    let serviceID: ServiceID
    let role: RecommendationRole

    var id: String { "\(runtime.rawValue)|\(modelID)|\(serviceID.rawValue)|\(role.rawValue)" }
}

struct LlamaModelSettings: Codable, Equatable, Sendable {
    var contextSize: Int
    var gpuLayers: Int
    var flashAttention: Bool
    var kvCacheKeyType: String
    var kvCacheValueType: String
    var cacheReuse: Int
    var batchSize: Int
    var ubatchSize: Int
    var threads: Int
    var threadsBatch: Int
    var generation: GenerationProfile

    static func defaults(for role: RecommendationRole) -> Self {
        .init(
            contextSize: role == .chat ? 16_384 : 8_192,
            gpuLayers: 99,
            flashAttention: true,
            kvCacheKeyType: "q8_0",
            kvCacheValueType: "q8_0",
            cacheReuse: 256,
            batchSize: 512,
            ubatchSize: 256,
            threads: 0,
            threadsBatch: 0,
            generation: role == .coding ? .autocompleteBalanced : .balanced
        )
    }
}

struct ModelSettingsProfile: Codable, Equatable, Sendable {
    let runtime: ModelRuntime
    let role: RecommendationRole
    var llama: LlamaModelSettings?

    static func defaults(runtime: ModelRuntime, role: RecommendationRole) -> Self {
        switch runtime {
        case .llamaCpp:
            return .init(runtime: runtime, role: role, llama: .defaults(for: role))
        }
    }
}
