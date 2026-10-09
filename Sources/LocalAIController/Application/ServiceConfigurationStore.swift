import Foundation

protocol ServiceConfigurationStoring: AnyObject {
    func load() -> [ServiceID: ServiceLaunchConfiguration]?
    func save(_ configurations: [ServiceID: ServiceLaunchConfiguration])
    func legacyChatPort() -> Int
}

final class UserDefaultsServiceConfigurationStore: ServiceConfigurationStoring {
    private let defaults: UserDefaults
    private let configurationKey = "serviceLaunchConfigurations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ServiceID: ServiceLaunchConfiguration]? {
        guard let data = defaults.data(forKey: configurationKey),
              let stored = try? JSONDecoder().decode([String: ServiceLaunchConfiguration].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            ServiceID(rawValue: key).map { ($0, value) }
        })
    }

    func save(_ configurations: [ServiceID: ServiceLaunchConfiguration]) {
        let stored = Dictionary(uniqueKeysWithValues: configurations.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: configurationKey)
    }

    func legacyChatPort() -> Int { defaults.integer(forKey: "llamaChatPort") }
}
