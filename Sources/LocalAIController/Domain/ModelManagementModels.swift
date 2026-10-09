import Foundation

struct ModelMetadata: Codable, Equatable, Sendable {
    var alias: String
    var role: RecommendationRole
    var assignedServices: Set<ServiceID>
    var isPinned: Bool

    init(alias: String, role: RecommendationRole, assignedServices: Set<ServiceID>, isPinned: Bool = false) {
        self.alias = alias
        self.role = role
        self.assignedServices = assignedServices
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case alias, role, assignedServices, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alias = try container.decode(String.self, forKey: .alias)
        role = try container.decode(RecommendationRole.self, forKey: .role)
        assignedServices = try container.decode(Set<ServiceID>.self, forKey: .assignedServices)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

struct ModelDownloadProgress: Equatable, Sendable {
    let completedBytes: Int64
    let expectedBytes: Int64?

    var fractionCompleted: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(expectedBytes), 0), 1)
    }
}

enum ModelManagementError: LocalizedError, Equatable {
    case unsupportedSource
    case runtimeUnavailable(String)
    case invalidModelIdentity
    case activeAssignment
    case unsafePath
    case commandFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource: "This model cannot be downloaded from its available source."
        case .runtimeUnavailable(let runtime): "\(runtime) is not installed or is not available on PATH."
        case .invalidModelIdentity: "The model has an invalid repository or filename."
        case .activeAssignment: "Stop services using this model before deleting it."
        case .unsafePath: "The model path is outside the managed cache and was not changed."
        case .commandFailed(let detail), .downloadFailed(let detail): detail
        }
    }
}

protocol ModelInventoryProviding: AnyObject, Sendable {
    func discover() async -> [DiscoveredModel]
}

protocol ModelMetadataStoring: AnyObject, Sendable {
    func loadMetadata() async -> [String: ModelMetadata]
    func saveMetadata(_ metadata: [String: ModelMetadata]) async
}

protocol ModelTransferring: AnyObject, Sendable {
    func download(_ recommendation: ModelRecommendation, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws
    func delete(_ model: DiscoveredModel) async throws
}

protocol ModelManaging: ModelInventoryProviding, ModelMetadataStoring, ModelTransferring {}
