import Foundation

struct ModelMetadata: Codable, Equatable, Sendable {
    var alias: String
    var role: RecommendationRole
    var assignedServices: Set<ServiceID>
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

protocol ModelManaging: AnyObject, Sendable {
    func discover() async -> [DiscoveredModel]
    func loadMetadata() async -> [String: ModelMetadata]
    func saveMetadata(_ metadata: [String: ModelMetadata]) async
    func download(_ recommendation: ModelRecommendation) async throws
    func delete(_ model: DiscoveredModel) async throws
}
