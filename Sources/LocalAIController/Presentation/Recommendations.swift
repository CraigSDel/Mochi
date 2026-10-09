import Foundation
import Combine
import UserNotifications

protocol RecommendationProvider: Sendable {
    var sourceName: String { get }
    func fetch() async throws -> [ModelRecommendation]
}

protocol ModelSearchProvider: Sendable {
    func search(query: String) async throws -> [ModelRecommendation]
}

@MainActor
final class RecommendationStore: ObservableObject {
    @Published private(set) var recommendations: [ModelRecommendation] = []
    @Published private(set) var status = "Not checked yet"
    @Published private(set) var isRefreshing = false
    @Published private(set) var searchResults: [ModelRecommendation] = []
    @Published private(set) var searchQuery = ""
    @Published private(set) var searchStatus = ""
    @Published private(set) var isSearching = false
    @Published private(set) var downloadQueue: [ModelRecommendation] = []
    @Published var lastChecked: Date?

    private let providers: [any RecommendationProvider]
    private let searchProvider: any ModelSearchProvider
    private let defaults: UserDefaults
    private let cacheURL: URL
    private let queueKey = "modelDownloadQueue.v1"
    private var catalogRecommendations: [ModelRecommendation] = []
    private var timer: Timer?

    init(
        providers: [any RecommendationProvider] = [CuratedLlamaCppProvider(), HuggingFaceProvider(), OllamaLibraryProvider()],
        searchProvider: (any ModelSearchProvider)? = nil,
        defaults: UserDefaults = .standard,
        cacheURL: URL? = nil,
        startTimer: Bool = true
    ) {
        self.providers = providers
        self.searchProvider = searchProvider ?? (providers.compactMap { $0 as? any ModelSearchProvider }.first ?? HuggingFaceProvider())
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Local AI Controller")
        self.cacheURL = cacheURL ?? base.appendingPathComponent("recommendations.json")
        loadDownloadQueue()
        loadCache()
        mergeCuratedRecommendationsIfEnabled()
        publishRecommendations()
        let stored = defaults.object(forKey: "recommendationsLastChecked") as? Date
        lastChecked = stored
        if stored == nil || Date().timeIntervalSince(stored!) >= 86_400 { Task { await refresh() } }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lastChecked == nil || Date().timeIntervalSince(self.lastChecked!) >= 86_400 else { return }
                await self.refresh()
            }
        } }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var combined: [ModelRecommendation] = []
        var failures: [String] = []
        var succeeded: Set<String> = []
        await withTaskGroup(of: (String, Result<[ModelRecommendation], Error>).self) { group in
            for provider in providers {
                group.addTask {
                    do { return (provider.sourceName, .success(try await provider.fetch())) }
                    catch { return (provider.sourceName, .failure(error)) }
                }
            }
            for await (name, result) in group {
                switch result {
                case .success(let models): combined += models; succeeded.insert(name)
                case .failure: failures.append(name)
                }
            }
        }
        guard !succeeded.isEmpty else {
            status = "Unavailable: \(failures.joined(separator: ", "))"; return
        }
        let retained = catalogRecommendations.filter { !succeeded.contains($0.source) }
        combined += retained
        let previous = Set(recommendations.map(\.id))
        catalogRecommendations = combined.sorted { lhs, rhs in
            if lhs.compatibility != rhs.compatibility { return lhs.compatibility.rawValue < rhs.compatibility.rawValue }
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        publishRecommendations()
        let newCompatible = combined.filter { $0.compatibility == .compatible && !previous.contains($0.id) }
        if !newCompatible.isEmpty && !previous.isEmpty { await notify(newCompatible) }
        lastChecked = Date(); defaults.set(lastChecked, forKey: "recommendationsLastChecked")
        status = failures.isEmpty ? "Checked both registries" : "Unavailable: \(failures.joined(separator: ", "))"
        saveCache()
    }

    func search(query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            clearSearch()
            return
        }
        isSearching = true
        searchQuery = normalized
        searchStatus = "Searching Hugging Face…"
        defer { isSearching = false }
        do {
            searchResults = Array((try await searchProvider.search(query: normalized)).prefix(PerformanceBudgets.maximumSearchResults))
            searchStatus = "Found \(searchResults.count) result\(searchResults.count == 1 ? "" : "s")"
        } catch {
            searchResults = []
            searchStatus = "Search unavailable. Check your connection and try again."
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchStatus = ""
    }

    func isQueued(_ model: ModelRecommendation) -> Bool {
        guard let key = queueKey(for: model) else { return false }
        return downloadQueue.contains { queueKey(for: $0) == key }
    }

    func canQueue(_ model: ModelRecommendation) -> Bool {
        model.compatibility != .incompatible && queueKey(for: model) != nil
    }

    func addToDownloadQueue(_ model: ModelRecommendation) {
        guard canQueue(model), !isQueued(model) else { return }
        downloadQueue.append(model)
        persistDownloadQueue()
        publishRecommendations()
    }

    func removeFromDownloadQueue(_ model: ModelRecommendation) {
        guard let key = queueKey(for: model) else { return }
        downloadQueue.removeAll { queueKey(for: $0) == key }
        persistDownloadQueue()
        publishRecommendations()
    }

    private func notify(_ models: [ModelRecommendation]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = "New compatible local models"
        content.body = models.prefix(3).map(\.name).joined(separator: ", ")
        try? await center.add(UNNotificationRequest(identifier: "models-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil))
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([ModelRecommendation].self, from: data) else { return }
        catalogRecommendations = decoded
    }
    private func mergeCuratedRecommendationsIfEnabled() {
        guard providers.contains(where: { $0.sourceName == CuratedLlamaCppProvider().sourceName }) else { return }
        let curatedIDs = Set(CuratedLlamaCppProvider.recommendations.map(\.id))
        catalogRecommendations.removeAll { curatedIDs.contains($0.id) }
        catalogRecommendations.insert(contentsOf: CuratedLlamaCppProvider.recommendations, at: 0)
    }
    private func saveCache() {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(catalogRecommendations) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private func publishRecommendations() {
        var published = catalogRecommendations
        let existing = Set(published.compactMap(queueKey(for:)))
        published += downloadQueue.filter { model in
            guard let key = queueKey(for: model) else { return false }
            return !existing.contains(key)
        }
        recommendations = Array(published.prefix(PerformanceBudgets.maximumRecommendations))
    }

    private func queueKey(for model: ModelRecommendation) -> String? {
        guard let repository = model.repository?.trimmingCharacters(in: .whitespacesAndNewlines),
              let filename = model.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !repository.isEmpty, !filename.isEmpty else { return nil }
        return "\(repository)|\(filename)"
    }

    private func loadDownloadQueue() {
        guard let data = defaults.data(forKey: queueKey),
              let decoded = try? JSONDecoder().decode([ModelRecommendation].self, from: data) else { return }
        var seen = Set<String>()
        downloadQueue = decoded.filter { model in
            guard canQueue(model), let key = queueKey(for: model) else { return false }
            return seen.insert(key).inserted
        }
    }

    private func persistDownloadQueue() {
        guard let data = try? JSONEncoder().encode(downloadQueue) else { return }
        defaults.set(data, forKey: queueKey)
    }
}
