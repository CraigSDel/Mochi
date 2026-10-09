import Foundation

protocol ModelSettingsStoring: Sendable {
  func load() async -> [ModelAssignmentKey: ModelSettingsProfile]
  func save(_ settings: [ModelAssignmentKey: ModelSettingsProfile]) async
}

final class UserDefaultsModelSettingsStore: ModelSettingsStoring, @unchecked Sendable {
  private let defaults: UserDefaults
  private let key = "modelAssignmentSettings.v1"

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() async -> [ModelAssignmentKey: ModelSettingsProfile] {
    guard let data = defaults.data(forKey: key),
      let stored = try? JSONDecoder().decode([String: StoredModelSettings].self, from: data)
    else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: stored.compactMap { item in
        guard let key = item.value.key else { return nil }
        return (key, item.value.profile)
      })
  }

  func save(_ settings: [ModelAssignmentKey: ModelSettingsProfile]) async {
    let stored = Dictionary(
      uniqueKeysWithValues: settings.map {
        ($0.key.id, StoredModelSettings(key: $0.key, profile: $0.value))
      })
    guard let data = try? JSONEncoder().encode(stored) else { return }
    defaults.set(data, forKey: key)
  }

  private struct StoredModelSettings: Codable {
    let runtime: ModelRuntime
    let modelID: String
    let serviceID: ServiceID
    let role: RecommendationRole
    let profile: ModelSettingsProfile

    init(key: ModelAssignmentKey, profile: ModelSettingsProfile) {
      runtime = key.runtime
      modelID = key.modelID
      serviceID = key.serviceID
      role = key.role
      self.profile = profile
    }

    var key: ModelAssignmentKey? {
      .init(runtime: runtime, modelID: modelID, serviceID: serviceID, role: role)
    }
  }
}
