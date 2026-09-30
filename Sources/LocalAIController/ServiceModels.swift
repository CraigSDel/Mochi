import Foundation

enum ServiceID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case llamaChat, autocomplete, embeddings, ollama
    var id: String { rawValue }
}

enum SidebarDestination: Hashable {
    case overview
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

enum ControllerPolicy {
    static let reserveBytes: UInt64 = 14 * 1_073_741_824
    static let maxModelBytes: UInt64 = 20 * 1_073_741_824
    static let kvCacheBytesPerToken: UInt64 = 48 * 1_024
    static let supportedArchitectures = [
        "llama", "qwen2", "qwen3", "mistral", "gemma", "phi3", "bert", "nomic-bert", "gpt-oss"
    ]

    static func validPort(_ port: Int) -> Bool { (1024...65535).contains(port) }
    static func fits(sizeBytes: Int64?, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Bool {
        guard let sizeBytes, sizeBytes > 0 else { return false }
        let available = physicalMemory > reserveBytes ? physicalMemory - reserveBytes : 0
        return UInt64(sizeBytes) <= min(maxModelBytes, available)
    }

    static func compatibility(sizeBytes: Int64?, architectureKnown: Bool, gated: Bool, multimodal: Bool, cloudOnly: Bool, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Compatibility {
        if gated || multimodal || cloudOnly { return .incompatible }
        guard architectureKnown, sizeBytes != nil else { return .unverified }
        return fits(sizeBytes: sizeBytes, physicalMemory: physicalMemory) ? .compatible : .incompatible
    }


    static func memoryAssessment(
        modelBytes: [Int64]?,
        contextSize: Int,
        parallelRequests: Int = 1,
        loadedModelCount: Int = 1,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> MemoryAssessment {
        let budget = physicalMemory > reserveBytes ? physicalMemory - reserveBytes : 0
        guard let modelBytes, !modelBytes.isEmpty, modelBytes.allSatisfy({ $0 > 0 }) else {
            return .init(
                severity: .unverified,
                estimatedBytes: nil,
                usableBudgetBytes: budget,
                message: "Memory use is unverified because model-size metadata is unavailable."
            )
        }

        let weights = modelBytes.reduce(UInt64(0)) { $0 + UInt64($1) }
        let contexts = UInt64(max(contextSize, 0))
        let requests = UInt64(max(parallelRequests, 1))
        let loaded = UInt64(max(loadedModelCount, 1))
        let kvCache = contexts.multipliedReportingOverflow(by: kvCacheBytesPerToken).partialValue
            .multipliedReportingOverflow(by: requests).partialValue
            .multipliedReportingOverflow(by: loaded).partialValue
        let estimated = weights.addingReportingOverflow(kvCache).partialValue
        let severity: MemoryRiskSeverity
        if budget == 0 || estimated > budget {
            severity = .high
        } else if Double(estimated) / Double(budget) >= 0.8 {
            severity = .caution
        } else {
            severity = .safe
        }

        let estimateText = ByteCountFormatter.string(fromByteCount: Int64(clamping: estimated), countStyle: .memory)
        let budgetText = ByteCountFormatter.string(fromByteCount: Int64(clamping: budget), countStyle: .memory)
        let message: String
        switch severity {
        case .safe:
            let headroom = ByteCountFormatter.string(fromByteCount: Int64(clamping: budget - estimated), countStyle: .memory)
            message = "Estimated memory: \(estimateText) of \(budgetText), with \(headroom) of headroom."
        case .caution:
            message = "Estimated memory: \(estimateText) of \(budgetText). Performance may degrade under memory pressure."
        case .high:
            message = "Estimated memory: \(estimateText), above the \(budgetText) safe budget. The Mac may swap heavily or the service may fail."
        case .unverified:
            message = "Memory use is unverified."
        }
        return .init(severity: severity, estimatedBytes: estimated, usableBudgetBytes: budget, message: message)
    }
}
