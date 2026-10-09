import Foundation
import Combine

@MainActor
final class ServiceManager: ObservableObject {
    static let startAllServiceIDs: [ServiceID] = [.llamaChat, .autocomplete, .embeddings]
    @Published var services: [ServiceSnapshot]
    @Published var configurations: [ServiceID: ServiceLaunchConfiguration]
    @Published private(set) var installedModels: [DiscoveredModel]
    @Published private(set) var modelMetadata: [String: ModelMetadata]
    @Published private(set) var modelSettings: [ModelAssignmentKey: ModelSettingsProfile]
    @Published private(set) var latestTailscaleDiagnostic: TailscaleDiagnostic?
    @Published private(set) var isTestingTailscale = false
    @Published var hardwareProfile: HardwareProfile?
    @Published var isRefreshingHardware = false
    @Published var hardwareTuningPlan: HardwareTuningPlan?
    @Published var hardwareApplyMessage = ""
    @Published var canRestoreHardwareTuning = false
    @Published var presentedFailure: ServiceFailure?
    @Published var launchAtLogin = false

    let fileManager: FileManager
    let probe: any SystemProbing
    let modelManager: any ModelManaging
    let modelSettingsStore: any ModelSettingsStoring
    let configurationStore: any ServiceConfigurationStoring
    let processController: ServiceProcessController
    let processStore: any ManagedProcessStoring
    let logStore: any ServiceLogStoring
    let logger: any ServiceLogging
    let defaults: UserDefaults
    let hardwareUndoKey = "hardwareTuningUndo"
    let stopPollAttempts: Int
    var validatedProcessRoots: [ServiceID: ManagedProcessRoot] = [:]
    var recommendationMetadata: [ModelRecommendation] = []
    var launchHosts: [ServiceID: (display: String, health: String)] = [:]
    var launchScripts: [ServiceID: URL] = [:]
    var timer: Timer?

    let definitions: [ServiceDefinition] = [
        .init(id: .llamaChat, name: "Qwen Chat", detail: "Qwen3.8-27B chat and reasoning", runtime: "llama.cpp", modelChoice: "chat", executable: "llama-server", estimatedBytes: 17_000_000_000, supported: true),
        .init(id: .autocomplete, name: "Code Autocomplete", detail: "Qwen2.5-Coder-1.5B", runtime: "llama.cpp", modelChoice: "autocomplete", executable: "llama-server", estimatedBytes: 1_200_000_000, supported: true),
        .init(id: .embeddings, name: "Workspace Embeddings", detail: "Nomic Embed Text v1.5", runtime: "llama.cpp", modelChoice: "embedding", executable: "llama-server", estimatedBytes: 300_000_000, supported: true),
        .init(id: .ollama, name: "Ollama", detail: "Installed chat, coding, and embedding models", runtime: "Ollama", modelChoice: nil, executable: "ollama", estimatedBytes: 17_000_000_000, supported: true)
    ]

    init(
        probe: (any SystemProbing)? = nil,
        processFactory: (any ProcessMaking)? = nil,
        logger: (any ServiceLogging)? = nil,
        modelManager: (any ModelManaging)? = nil,
        modelSettingsStore: (any ModelSettingsStoring)? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        startTimer: Bool = true,
        stopPollAttempts: Int = 20,
        processStore: (any ManagedProcessStoring)? = nil,
        logStore: (any ServiceLogStoring)? = nil,
        configurationStore: (any ServiceConfigurationStoring)? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.stopPollAttempts = stopPollAttempts
        self.logger = logger ?? LiveServiceLogger()
        let resolvedProbe = probe ?? LiveSystemProbe(fileManager: fileManager)
        self.probe = resolvedProbe
        self.processController = ServiceProcessController(factory: processFactory ?? LiveProcessFactory())
        self.processStore = processStore ?? FileManagedProcessStore(directory: resolvedProbe.supportDirectory)
        self.logStore = logStore ?? FileServiceLogStore(directory: resolvedProbe.supportDirectory, fileManager: fileManager)
        self.configurationStore = configurationStore ?? UserDefaultsServiceConfigurationStore(defaults: defaults)
        self.modelManager = modelManager ?? (probe == nil ? LiveModelManager(fileManager: fileManager) : ProbeModelManager(probe: resolvedProbe))
        self.modelSettingsStore = modelSettingsStore ?? UserDefaultsModelSettingsStore(defaults: defaults)
        self.installedModels = []
        self.modelMetadata = [:]
        self.modelSettings = [:]
        self.canRestoreHardwareTuning = defaults.data(forKey: hardwareUndoKey) != nil

        var loaded = self.configurationStore.load()
        if loaded == nil {
            var initial = Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { ($0, ServiceLaunchConfiguration.defaultValue(for: $0)) })
            let legacyPort = self.configurationStore.legacyChatPort()
            if legacyPort != 0 { initial[.llamaChat]?.port = legacyPort }
            loaded = initial
        }
        var resolvedConfigurations = loaded ?? [:]
        for id in ServiceID.allCases where resolvedConfigurations[id] == nil {
            resolvedConfigurations[id] = .defaultValue(for: id)
        }
        for id in ServiceID.allCases {
            if let context = resolvedConfigurations[id]?.llama?.contextSize {
                resolvedConfigurations[id]?.llama?.contextSize = ContextSizeOptions.normalized(context)
            } else if let context = resolvedConfigurations[id]?.ollama?.contextLength {
                resolvedConfigurations[id]?.ollama?.contextLength = ContextSizeOptions.normalized(context)
            }
        }
        configurations = resolvedConfigurations
        services = definitions.map { ServiceSnapshot(definition: $0) }
        persistConfigurations()
        for index in services.indices {
            self.logStore.ensureLog(for: services[index].id)
            services[index].logText = self.logStore.tail(services[index].id)
        }

        Task { [weak self] in
            guard let self else { return }
            self.installedModels = await self.modelManager.discover()
            self.modelMetadata = await self.modelManager.loadMetadata()
            self.modelSettings = await self.modelSettingsStore.load()
            Task { @MainActor [weak self] in await self?.refreshHardwareProfile() }
            await self.refreshStatuses()
        }
        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: PerformanceBudgets.servicePollingInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.refreshStatuses() }
            }
        }
    }

    var managedProcessMemoryRoots: [ServiceID: ManagedProcessRoot] { validatedProcessRoots }
    func configuration(for id: ServiceID) -> ServiceLaunchConfiguration { configurations[id] ?? .defaultValue(for: id) }
    func replaceInstalledModels(_ models: [DiscoveredModel]) {
        installedModels = models
        rebuildHardwareTuningPlan()
    }
    func replaceModelMetadata(_ metadata: [String: ModelMetadata]) { modelMetadata = metadata }
    func replaceModelSettings(_ settings: [ModelAssignmentKey: ModelSettingsProfile]) { modelSettings = settings }

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
        guard let ollama = config.ollama else {
            return ControllerPolicy.memoryAssessment(modelBytes: nil, contextSize: 0, physicalMemory: probe.physicalMemory)
        }
        let selection = OllamaMemoryModelSelection.resolve(
            configuration: ollama,
            installedModels: installedModels,
            recommendations: recommendationMetadata,
            isDefaultConfiguration: config == .defaultValue(for: .ollama),
            defaultSize: definition(for: id)?.estimatedBytes
        )
        return ControllerPolicy.memoryAssessment(
            modelBytes: selection.modelBytes,
            contextSize: ollama.contextLength,
            parallelRequests: ollama.parallelRequests,
            loadedModelCount: selection.loadedModelCount,
            physicalMemory: probe.physicalMemory
        )
    }

    func performanceGuidance() -> [PerformanceGuidance] {
        PerformanceGuidanceBuilder.make(
            configurations: configurations,
            installedModels: installedModels,
            recommendations: recommendationMetadata,
            physicalMemory: probe.physicalMemory,
            defaultLlamaConfiguration: ServiceLaunchConfiguration.defaultValue(for: .llamaChat).llama,
            defaultLlamaSize: definition(for: .llamaChat)?.estimatedBytes,
            defaultOllamaSize: definition(for: .ollama)?.estimatedBytes
        )
    }

    @discardableResult
    func testTailscale() async -> TailscaleDiagnostic {
        isTestingTailscale = true
        latestTailscaleDiagnostic = .init(status: .checking, peer: nil, detail: "Testing an online peer…", checkedAt: Date())
        let result = await probe.tailscaleDiagnostic()
        latestTailscaleDiagnostic = result
        isTestingTailscale = false
        return result
    }

    func tailscaleLaunchWarning(for ids: [ServiceID], bindModeOverride: BindMode? = nil) async -> LaunchWarning? {
        guard let serviceID = ids.first(where: {
            (bindModeOverride ?? configuration(for: $0).bindMode) == .tailscale
        }) else { return nil }
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
        guard let ollama = configuration.ollama else { return [] }
        let installedKeys = Set(installedModels.filter { $0.runtime == .ollama }.map { OllamaModelReference.key($0.name) })
        return [ollama.chatModel, ollama.autocompleteModel, ollama.embeddingModel].filter { !installedKeys.contains(OllamaModelReference.key($0)) }
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
            if bindMode == .lan {
                warnings.append(.init(serviceID: id, message: "\(serviceName(id)) will expose an unauthenticated API to the local network."))
            }
            let assessment = memoryAssessment(for: id)
            if assessment.requiresConfirmation {
                warnings.append(.init(serviceID: id, message: "\(serviceName(id)): \(assessment.message)"))
            }
            return warnings
        }
    }

    static func effectiveBindMode(configured: BindMode, override: BindMode?, overrideSavedMode: Bool = false) -> BindMode {
        if overrideSavedMode, let override, override == .tailscale || override == .localhost { return override }
        guard configured == .tailscale, let override, override == .localhost || override == .lan else { return configured }
        return override
    }

    func clearLog(_ id: ServiceID) {
        logStore.clear(id, handle: processController.outputHandles[id])
        if let index = services.firstIndex(where: { $0.id == id }) { services[index].logText = "" }
    }

    func logURL(_ id: ServiceID) -> URL { logStore.logURL(for: id) }
    func save(_ record: ManagedProcessRecord) { processStore.save(record) }

    static func endpoint(_ id: ServiceID, _ port: Int, _ host: String) -> String {
        id == .ollama ? "http://\(host):\(port)" : "http://\(host):\(port)/v1"
    }

    func persistConfigurations() {
        configurationStore.save(configurations)
    }

}
