import Foundation
import UserNotifications

protocol RecommendationCaching: AnyObject {
    func load() -> [ModelRecommendation]
    func save(_ recommendations: [ModelRecommendation])
    func lastChecked() -> Date?
    func setLastChecked(_ date: Date)
}

final class FileRecommendationCache: RecommendationCaching {
    private let defaults: UserDefaults
    private let cacheURL: URL

    init(defaults: UserDefaults = .standard, cacheURL: URL) {
        self.defaults = defaults
        self.cacheURL = cacheURL
    }

    static func standard(defaults: UserDefaults = .standard) -> Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Local AI Controller")
        return .init(defaults: defaults, cacheURL: base.appendingPathComponent("recommendations.json"))
    }

    func load() -> [ModelRecommendation] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([ModelRecommendation].self, from: data)) ?? []
    }

    func save(_ recommendations: [ModelRecommendation]) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(recommendations) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    func lastChecked() -> Date? { defaults.object(forKey: "recommendationsLastChecked") as? Date }
    func setLastChecked(_ date: Date) { defaults.set(date, forKey: "recommendationsLastChecked") }
}

protocol RecommendationNotifying: Sendable {
    func notifyNewCompatibleModels(_ models: [ModelRecommendation]) async
}

struct UserNotificationRecommendationNotifier: RecommendationNotifying {
    func notifyNewCompatibleModels(_ models: [ModelRecommendation]) async {
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
        try? await center.add(UNNotificationRequest(
            identifier: "models-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        ))
    }
}
