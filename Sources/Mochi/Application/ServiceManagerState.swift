import Foundation

@MainActor
extension ServiceManager {
    var managedProcessMemoryRoots: [ServiceID: ManagedProcessRoot] { validatedProcessRoots }

    func configuration(for id: ServiceID) -> ServiceLaunchConfiguration { configurations[id] ?? .defaultValue(for: id) }

    func isConfigurationLocked(_ id: ServiceID) -> Bool {
        services.first(where: { $0.id == id }).map { [.starting, .running, .stopping].contains($0.state) } ?? false
    }

    func updateConfiguration(_ configuration: ServiceLaunchConfiguration, for id: ServiceID) {
        guard !isConfigurationLocked(id) else { return }
        configurations[id] = configuration
        persistConfigurations()
    }

    func resetConfiguration(_ id: ServiceID) { updateConfiguration(.defaultValue(for: id), for: id) }
    func wifiIP() async -> String? { await probe.wifiIP() }

    func localNetworkIP() async -> String? {
        if let wifi = await probe.wifiIP() { return wifi }
        return await probe.localNetworkIP()
    }

    func clearLog(_ id: ServiceID) {
        logStore.clear(id, handle: processController.outputHandles[id])
        if let index = services.firstIndex(where: { $0.id == id }) { services[index].logText = "" }
    }

    func logURL(_ id: ServiceID) -> URL { logStore.logURL(for: id) }
    func save(_ record: ManagedProcessRecord) { processStore.save(record) }

    static func endpoint(_ id: ServiceID, _ port: Int, _ host: String) -> String {
        "http://\(host):\(port)/v1"
    }

    func persistConfigurations() { configurationStore.save(configurations) }
}
