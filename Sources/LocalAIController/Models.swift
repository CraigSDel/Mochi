import Foundation

enum ServiceID: String, Codable, CaseIterable, Identifiable, Sendable {
    case llamaChat, autocomplete, embeddings, ollama
    var id: String { rawValue }
}

enum ServiceState: String, Codable, Sendable {
    case unavailable, stopped, starting, running, stopping, failed, external
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
}

enum RecommendationRole: String, Codable, CaseIterable, Sendable {
    case chat = "Chat / reasoning"
    case coding = "Coding / autocomplete"
    case embedding = "Embeddings"
}

enum Compatibility: String, Codable, Sendable {
    case compatible = "Compatible"
    case unverified = "Unverified"
    case incompatible = "Incompatible"
}

struct ModelRecommendation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let source: String
    let runtime: String
    let role: RecommendationRole
    let quantization: String
    let sizeBytes: Int64?
    let context: String
    let license: String
    let compatibility: Compatibility
    let rationale: String
    let updatedAt: Date?
    var sizeText: String {
        guard let sizeBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum ControllerPolicy {
    static let reserveBytes: UInt64 = 14 * 1_073_741_824
    static let maxModelBytes: UInt64 = 20 * 1_073_741_824
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
}
