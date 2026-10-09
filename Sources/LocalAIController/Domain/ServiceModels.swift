import Foundation

enum ServiceID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case llamaChat, autocomplete, embeddings, ollama
    var id: String { rawValue }
}

enum SidebarDestination: Hashable {
    case overview
    case models
    case service(ServiceID)
    case recommendations

    static let initial: SidebarDestination = .overview
}

enum ServiceState: String, Codable, Sendable {
    case unavailable, stopped, starting, running, stopping, failed, external

    var displayName: String {
        switch self {
        case .unavailable: "Unavailable"
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .failed: "Needs attention"
        case .external: "External"
        }
    }

    var symbolName: String {
        switch self {
        case .unavailable: "slash.circle.fill"
        case .stopped: "circle"
        case .starting, .stopping: "clock.fill"
        case .running: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .external: "link.circle.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .running: .success
        case .starting, .stopping: .warning
        case .failed: .danger
        case .external: .accent
        case .unavailable, .stopped: .neutral
        }
    }

    var canStart: Bool { [.stopped, .failed, .unavailable].contains(self) }
    var canStop: Bool { [.running, .starting].contains(self) }
}

enum StatusTone: String, CaseIterable, Sendable {
    case accent, success, warning, danger, neutral
}

extension ServiceID {
    var symbolName: String {
        switch self {
        case .llamaChat: "bubble.left.and.bubble.right.fill"
        case .autocomplete: "chevron.left.forwardslash.chevron.right"
        case .embeddings: "point.3.connected.trianglepath.dotted"
        case .ollama: "shippingbox.fill"
        }
    }
}

enum BindMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case tailscale, localhost, lan
    var id: String { rawValue }
    var title: String {
        switch self { case .tailscale: "Tailscale"; case .localhost: "Localhost"; case .lan: "Local network" }
    }
}

enum DownloadPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case cachedOnly, allowDownloads
    var id: String { rawValue }
    var title: String { self == .cachedOnly ? "Cached only" : "Allow downloads" }
}

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

struct OllamaLaunchConfiguration: Codable, Equatable, Sendable {
    var chatModel: String
    var autocompleteModel: String
    var embeddingModel: String
    var flashAttention: Bool
    var kvCacheType: String
    var contextLength: Int
    var parallelRequests: Int
    var maxLoadedModels: Int
    var chatGeneration: GenerationProfile
    var autocompleteGeneration: GenerationProfile

    init(
        chatModel: String, autocompleteModel: String, embeddingModel: String,
        flashAttention: Bool, kvCacheType: String, contextLength: Int,
        parallelRequests: Int, maxLoadedModels: Int,
        chatGeneration: GenerationProfile = .balanced,
        autocompleteGeneration: GenerationProfile = .autocompleteBalanced
    ) {
        self.chatModel = chatModel; self.autocompleteModel = autocompleteModel
        self.embeddingModel = embeddingModel; self.flashAttention = flashAttention
        self.kvCacheType = kvCacheType; self.contextLength = contextLength
        self.parallelRequests = parallelRequests; self.maxLoadedModels = maxLoadedModels
        self.chatGeneration = chatGeneration; self.autocompleteGeneration = autocompleteGeneration
    }

    private enum CodingKeys: String, CodingKey {
        case chatModel, autocompleteModel, embeddingModel, flashAttention, kvCacheType
        case contextLength, parallelRequests, maxLoadedModels, chatGeneration, autocompleteGeneration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chatModel = try c.decode(String.self, forKey: .chatModel)
        autocompleteModel = try c.decode(String.self, forKey: .autocompleteModel)
        embeddingModel = try c.decode(String.self, forKey: .embeddingModel)
        flashAttention = try c.decodeIfPresent(Bool.self, forKey: .flashAttention) ?? true
        kvCacheType = try c.decodeIfPresent(String.self, forKey: .kvCacheType) ?? "q8_0"
        contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength) ?? 16_384
        parallelRequests = try c.decodeIfPresent(Int.self, forKey: .parallelRequests) ?? 2
        maxLoadedModels = try c.decodeIfPresent(Int.self, forKey: .maxLoadedModels) ?? 1
        chatGeneration = try c.decodeIfPresent(GenerationProfile.self, forKey: .chatGeneration) ?? .balanced
        autocompleteGeneration = try c.decodeIfPresent(GenerationProfile.self, forKey: .autocompleteGeneration) ?? .autocompleteBalanced
    }
}

struct ServiceLaunchConfiguration: Codable, Equatable, Sendable {
    var port: Int
    var bindMode: BindMode
    var downloadPolicy: DownloadPolicy
    var llama: LlamaLaunchConfiguration?
    var ollama: OllamaLaunchConfiguration?

    static func defaultValue(for id: ServiceID) -> Self {
        let common = (BindMode.tailscale, DownloadPolicy.cachedOnly)
        switch id {
        case .llamaChat:
            return .init(port: 11437, bindMode: common.0, downloadPolicy: common.1, llama: .init(repository: "unsloth/Qwen3.8-27B-GGUF", filename: "Qwen3.8-27B-UD-Q4_K_M.gguf", alias: "Qwen3.8-27B", contextSize: 16_384, gpuLayers: 99), ollama: nil)
        case .autocomplete:
            return .init(port: 11435, bindMode: common.0, downloadPolicy: common.1, llama: .init(repository: "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF", filename: "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf", alias: "Qwen2.5-Coder-1.5B", contextSize: 8_192, gpuLayers: 99), ollama: nil)
        case .embeddings:
            return .init(port: 11436, bindMode: common.0, downloadPolicy: common.1, llama: .init(repository: "nomic-ai/nomic-embed-text-v1.5-GGUF", filename: "nomic-embed-text-v1.5.Q8_0.gguf", alias: "nomic-embed-text", contextSize: 8_192, gpuLayers: 99), ollama: nil)
        case .ollama:
            return .init(port: 11434, bindMode: common.0, downloadPolicy: common.1, llama: nil, ollama: .init(chatModel: "qwen3.8:27b", autocompleteModel: "qwen2.5-coder:1.5b", embeddingModel: "nomic-embed-text:v1.5", flashAttention: true, kvCacheType: "q8_0", contextLength: 16_384, parallelRequests: 2, maxLoadedModels: 1))
        }
    }

    func hasCustomModels(comparedTo defaults: Self) -> Bool {
        if let llama, let baseline = defaults.llama {
            return llama.repository != baseline.repository || llama.filename != baseline.filename || llama.alias != baseline.alias
        }
        if let ollama, let baseline = defaults.ollama {
            return ollama.chatModel != baseline.chatModel || ollama.autocompleteModel != baseline.autocompleteModel || ollama.embeddingModel != baseline.embeddingModel
        }
        return false
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
    let defaultPort: Int?
    let modelChoice: String?
    let executable: String?
    let modelFormat: String
    let estimatedBytes: Int64?
    let supported: Bool
    let unavailableReason: String?
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

struct ManagedProcessRecord: Codable, Sendable {
    let serviceID: ServiceID
    let pid: Int32
    let port: Int
    let expectedCommand: String
    let startedAt: Date
    let logPath: String
    let bindMode: BindMode?
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
