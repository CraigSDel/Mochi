import Foundation
import Combine
import UserNotifications

protocol RecommendationProvider: Sendable {
    var sourceName: String { get }
    func fetch() async throws -> [ModelRecommendation]
}

@MainActor
final class RecommendationStore: ObservableObject {
    @Published private(set) var recommendations: [ModelRecommendation] = []
    @Published private(set) var status = "Not checked yet"
    @Published private(set) var isRefreshing = false
    @Published var lastChecked: Date?

    private let providers: [any RecommendationProvider]
    private let defaults: UserDefaults
    private let cacheURL: URL
    private var timer: Timer?

    init(
        providers: [any RecommendationProvider] = [CuratedLlamaCppProvider(), HuggingFaceProvider(), OllamaLibraryProvider()],
        defaults: UserDefaults = .standard,
        cacheURL: URL? = nil,
        startTimer: Bool = true
    ) {
        self.providers = providers
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Local AI Controller")
        self.cacheURL = cacheURL ?? base.appendingPathComponent("recommendations.json")
        loadCache()
        mergeCuratedRecommendationsIfEnabled()
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
        let retained = recommendations.filter { !succeeded.contains($0.source) }
        combined += retained
        let previous = Set(recommendations.map(\.id))
        recommendations = combined.sorted { lhs, rhs in
            if lhs.compatibility != rhs.compatibility { return lhs.compatibility.rawValue < rhs.compatibility.rawValue }
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        let newCompatible = combined.filter { $0.compatibility == .compatible && !previous.contains($0.id) }
        if !newCompatible.isEmpty && !previous.isEmpty { await notify(newCompatible) }
        lastChecked = Date(); defaults.set(lastChecked, forKey: "recommendationsLastChecked")
        status = failures.isEmpty ? "Checked both registries" : "Unavailable: \(failures.joined(separator: ", "))"
        saveCache()
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
        recommendations = decoded
    }
    private func mergeCuratedRecommendationsIfEnabled() {
        guard providers.contains(where: { $0.sourceName == CuratedLlamaCppProvider().sourceName }) else { return }
        let curatedIDs = Set(CuratedLlamaCppProvider.recommendations.map(\.id))
        recommendations.removeAll { curatedIDs.contains($0.id) }
        recommendations.insert(contentsOf: CuratedLlamaCppProvider.recommendations, at: 0)
    }
    private func saveCache() {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(recommendations) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
