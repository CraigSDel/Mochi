import Foundation

protocol ModelDownloadQueueStoring: AnyObject, Sendable {
    func load() async -> [ModelRecommendation]
    func save(_ recommendations: [ModelRecommendation]) async
}

final class UserDefaultsModelDownloadQueueStore: ModelDownloadQueueStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "modelDownloadQueue.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() async -> [ModelRecommendation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ModelRecommendation].self, from: data)) ?? []
    }

    func save(_ recommendations: [ModelRecommendation]) async {
        guard let data = try? JSONEncoder().encode(recommendations) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
protocol ModelDownloadExecuting: AnyObject {
    func downloadModel(
        _ recommendation: ModelRecommendation,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
}
