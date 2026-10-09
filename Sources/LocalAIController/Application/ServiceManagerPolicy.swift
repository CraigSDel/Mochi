import Foundation

@MainActor
extension ServiceManager {
    func memoryAssessment(for id: ServiceID) -> MemoryAssessment {
        let config = configuration(for: id)
        if let llama = config.llama {
            let settings = modelSettings(for: id).llama
            return ControllerPolicy.memoryAssessment(
                modelBytes: llamaModelSize(llama, serviceID: id).map { [$0] },
                contextSize: settings?.contextSize ?? llama.contextSize,
                cacheReuse: settings?.cacheReuse ?? llama.cacheReuse,
                physicalMemory: probe.physicalMemory
            )
        }
        return ControllerPolicy.memoryAssessment(modelBytes: nil, contextSize: 0, physicalMemory: probe.physicalMemory)
    }

    func performanceGuidance() -> [PerformanceGuidance] {
        PerformanceGuidanceBuilder.make(
            configurations: configurations,
            installedModels: installedModels,
            recommendations: recommendationMetadata,
            physicalMemory: probe.physicalMemory,
            defaultLlamaConfiguration: ServiceLaunchConfiguration.defaultValue(for: .llamaChat).llama,
            defaultLlamaSize: definition(for: .llamaChat)?.estimatedBytes,
        )
    }

    func tailscaleLaunchWarning(for ids: [ServiceID], bindModeOverride: BindMode? = nil) async -> LaunchWarning? {
        guard let serviceID = ids.first(where: { (bindModeOverride ?? configuration(for: $0).bindMode) == .tailscale }) else { return nil }
        let diagnostic = await testTailscale()
        return diagnostic.launchWarning.map { .init(serviceID: serviceID, message: $0) }
    }

    func enableDownloads(for ids: [ServiceID]) {
        for id in ids {
            var configuration = self.configuration(for: id)
            guard !isConfigurationLocked(id) else { continue }
            configuration.downloadPolicy = .allowDownloads
            configurations[id] = configuration
        }
        persistConfigurations()
    }

    func modelsRequiringDownload(for id: ServiceID) -> [String] {
        let configuration = configuration(for: id)
        guard configuration.downloadPolicy == .cachedOnly else { return [] }
        if let llama = configuration.llama {
            let installed = installedModels.contains { $0.runtime == .llamaCpp && $0.repository == llama.repository && $0.filename == llama.filename }
            return installed ? [] : [llama.alias]
        }
        return []
    }

    func validationIssuesForStartAll() -> [ConfigurationIssue] {
        let ids = Self.startAllServiceIDs
        var issues = ids.flatMap { id in
            validationIssues(for: id).map { ConfigurationIssue(field: "\(id.rawValue).\($0.field)", message: "\(serviceName(id)): \($0.message)") }
        }
        for (port, conflictingIDs) in Dictionary(grouping: ids, by: { configuration(for: $0).port }) where conflictingIDs.count > 1 {
            issues.append(.init(field: "ports", message: "Port \(port) is assigned to \(conflictingIDs.map(serviceName).joined(separator: ", "))."))
        }
        return issues
    }

    func launchWarnings(for ids: [ServiceID], bindModeOverride: BindMode? = nil) -> [LaunchWarning] {
        ids.flatMap { id -> [LaunchWarning] in
            let config = configuration(for: id)
            var warnings: [LaunchWarning] = []
            let bindMode = bindModeOverride ?? config.bindMode
            if bindMode == .lan { warnings.append(.init(serviceID: id, message: "\(serviceName(id)) will expose an unauthenticated API to the local network.")) }
            let assessment = memoryAssessment(for: id)
            if assessment.requiresConfirmation { warnings.append(.init(serviceID: id, message: "\(serviceName(id)): \(assessment.message)")) }
            return warnings
        }
    }

    static func effectiveBindMode(configured: BindMode, override: BindMode?, overrideSavedMode: Bool = false) -> BindMode {
        if overrideSavedMode, let override, override == .tailscale || override == .localhost { return override }
        guard configured == .tailscale, let override, override == .localhost || override == .lan else { return configured }
        return override
    }
}
