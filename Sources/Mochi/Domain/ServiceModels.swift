import Foundation

struct LlamaLaunchConfiguration: Codable, Equatable, Sendable {
    var repository: String
    var filename: String
    var alias: String
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

    init(
        repository: String, filename: String, alias: String, contextSize: Int,
        gpuLayers: Int, flashAttention: Bool = true, kvCacheKeyType: String = "q8_0",
        kvCacheValueType: String = "q8_0", cacheReuse: Int = 256, batchSize: Int = 512,
        ubatchSize: Int = 256, threads: Int = 0, threadsBatch: Int = 0,
        generation: GenerationProfile = .balanced
    ) {
        self.repository = repository; self.filename = filename; self.alias = alias
        self.contextSize = contextSize; self.gpuLayers = gpuLayers
        self.flashAttention = flashAttention; self.kvCacheKeyType = kvCacheKeyType
        self.kvCacheValueType = kvCacheValueType; self.cacheReuse = cacheReuse
        self.batchSize = batchSize; self.ubatchSize = ubatchSize; self.threads = threads
        self.threadsBatch = threadsBatch; self.generation = generation
    }

    private enum CodingKeys: String, CodingKey {
        case repository, filename, alias, contextSize, gpuLayers, flashAttention
        case kvCacheKeyType, kvCacheValueType, cacheReuse, batchSize, ubatchSize
        case threads, threadsBatch, generation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repository = try c.decode(String.self, forKey: .repository)
        filename = try c.decode(String.self, forKey: .filename)
        alias = try c.decode(String.self, forKey: .alias)
        contextSize = try c.decode(Int.self, forKey: .contextSize)
        gpuLayers = try c.decode(Int.self, forKey: .gpuLayers)
        flashAttention = try c.decodeIfPresent(Bool.self, forKey: .flashAttention) ?? true
        kvCacheKeyType = try c.decodeIfPresent(String.self, forKey: .kvCacheKeyType) ?? "q8_0"
        kvCacheValueType = try c.decodeIfPresent(String.self, forKey: .kvCacheValueType) ?? "q8_0"
        cacheReuse = try c.decodeIfPresent(Int.self, forKey: .cacheReuse) ?? 256
        batchSize = try c.decodeIfPresent(Int.self, forKey: .batchSize) ?? 512
        ubatchSize = try c.decodeIfPresent(Int.self, forKey: .ubatchSize) ?? 256
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? 0
        threadsBatch = try c.decodeIfPresent(Int.self, forKey: .threadsBatch) ?? 0
        generation = try c.decodeIfPresent(GenerationProfile.self, forKey: .generation) ?? .balanced
    }
}

struct ServiceLaunchConfiguration: Codable, Equatable, Sendable {
    var port: Int
    var bindMode: BindMode
    var downloadPolicy: DownloadPolicy
    var llama: LlamaLaunchConfiguration?

    static func defaultValue(for id: ServiceID) -> Self {
        let common = (BindMode.tailscale, DownloadPolicy.cachedOnly)
        switch id {
        case .llamaChat:
            return .init(port: 11437, bindMode: common.0, downloadPolicy: common.1, llama: .init(repository: "unsloth/Qwen3.8-27B-GGUF", filename: "Qwen3.8-27B-UD-Q4_K_M.gguf", alias: "Qwen3.8-27B", contextSize: 16_384, gpuLayers: 99))
        case .autocomplete:
            return .init(port: 11435, bindMode: common.0, downloadPolicy: common.1, llama: .init(repository: "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF", filename: "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf", alias: "Qwen2.5-Coder-1.5B", contextSize: 8_192, gpuLayers: 99))
        case .embeddings:
            return .init(port: 11436, bindMode: common.0, downloadPolicy: common.1, llama: .init(repository: "nomic-ai/nomic-embed-text-v1.5-GGUF", filename: "nomic-embed-text-v1.5.Q8_0.gguf", alias: "nomic-embed-text", contextSize: 8_192, gpuLayers: 99))
        }
    }

}

struct ConfigurationIssue: Identifiable, Equatable, Sendable {
    let field: String
    let message: String
    var id: String { "\(field):\(message)" }
}

struct LaunchWarning: Identifiable, Equatable, Sendable {
    let serviceID: ServiceID
    let message: String
    var id: String { "\(serviceID.rawValue):\(message)" }
}

enum ContextSizeOptions {
    static let values = [4_096, 8_192, 16_384, 32_768, 65_536, 131_072, 262_144]

    static func normalized(_ value: Int) -> Int {
        values.min { abs($0 - value) < abs($1 - value) } ?? values[0]
    }

    static func label(for value: Int) -> String {
        "\(normalized(value) / 1_024)K"
    }
}

enum MemoryRiskSeverity: String, Equatable, Sendable {
    case safe, caution, high, unverified
}

struct MemoryAssessment: Equatable, Sendable {
    let severity: MemoryRiskSeverity
    let estimatedBytes: UInt64?
    let usableBudgetBytes: UInt64
    let message: String

    var requiresConfirmation: Bool { severity != .safe }
}

struct ServiceDefinition: Identifiable, Sendable {
    let id: ServiceID
    let name: String
    let detail: String
    let runtime: String
    let modelChoice: String?
    let executable: String?
    let estimatedBytes: Int64?
    let supported: Bool
}

struct ServiceSnapshot: Identifiable, Sendable {
    let definition: ServiceDefinition
    var state: ServiceState = .stopped
    var statusText = "Stopped"
    var pid: Int32?
    var endpoint: String?
    var logText = ""
    var id: ServiceID { definition.id }
}

struct ServiceFailure: Identifiable, Sendable {
    let serviceID: ServiceID
    let serviceName: String
    let message: String
    let guidance: String
    let timestamp: Date
    let logURL: URL
    var id: String { "\(serviceID.rawValue)-\(timestamp.timeIntervalSince1970)" }
}
