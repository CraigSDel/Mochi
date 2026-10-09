import Foundation

enum RecommendationRole: String, Codable, CaseIterable, Sendable {
    case chat = "Chat / reasoning"
    case coding = "Coding / autocomplete"
    case embedding = "Embeddings"
}
enum ModelRuntime: String, Codable, Sendable {
    case llamaCpp
    case ollama
}
struct DiscoveredModel: Identifiable, Hashable, Sendable {
    let runtime: ModelRuntime
    let name: String
    let repository: String?
    let filename: String?
    let sizeBytes: Int64?
    let roleHint: RecommendationRole
    /// Detected from local metadata only: an Ollama projector manifest layer, or
    /// an `mmproj-*.gguf` sibling in a Hugging Face snapshot.
    let supportsVision: Bool

    var id: String {
        switch runtime {
        case .llamaCpp: "llama:\(repository ?? ""):\(filename ?? name)"
        case .ollama: "ollama:\(name)"
        }
    }
}
enum ModelAvailability: String, Sendable {
    case installed = "Installed"
    case catalog = "Download required"
    case custom = "Custom"
    case missing = "Unavailable"
    case unsupported = "Multimodal (not supported)"
}

struct ModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let runtime: ModelRuntime
    let name: String
    let repository: String?
    let filename: String?
    let sizeBytes: Int64?
    let roleHint: RecommendationRole
    let availability: ModelAvailability

    var detail: String {
        let size = sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [availability.rawValue, size, roleHint.rawValue].compactMap { $0 }.joined(separator: " · ")
    }
}

enum Compatibility: String, Codable, Sendable {
    case compatible = "Compatible"
    case unverified = "Unverified"
    case incompatible = "Incompatible"
}

enum RecommendationCompatibilityFilter: String, Codable, CaseIterable, Sendable {
    case all
    case compatibleOnly

    func includes(_ recommendation: ModelRecommendation) -> Bool {
        self == .all || recommendation.compatibility == .compatible
    }

    func apply(to recommendations: [ModelRecommendation], role: RecommendationRole? = nil) -> [ModelRecommendation] {
        recommendations.filter { recommendation in
            includes(recommendation) && (role == nil || recommendation.role == role)
        }
    }
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
    let repository: String?
    let filename: String?
    let modelName: String?

    init(
        id: String, name: String, source: String, runtime: String, role: RecommendationRole,
        quantization: String, sizeBytes: Int64?, context: String, license: String,
        compatibility: Compatibility, rationale: String, updatedAt: Date?,
        repository: String? = nil, filename: String? = nil, modelName: String? = nil
    ) {
        self.id = id; self.name = name; self.source = source; self.runtime = runtime; self.role = role
        self.quantization = quantization; self.sizeBytes = sizeBytes; self.context = context; self.license = license
        self.compatibility = compatibility; self.rationale = rationale; self.updatedAt = updatedAt
        self.repository = repository; self.filename = filename; self.modelName = modelName
    }
    var sizeText: String {
        guard let sizeBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
