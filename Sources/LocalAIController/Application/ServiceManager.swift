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

    func replaceInstalledModels(_ models: [DiscoveredModel]) {
        installedModels = models
        rebuildHardwareTuningPlan()
    }

    func replaceModelMetadata(_ metadata: [String: ModelMetadata]) { modelMetadata = metadata }
    func replaceModelSettings(_ settings: [ModelAssignmentKey: ModelSettingsProfile]) { modelSettings = settings }

    @discardableResult
    func testTailscale() async -> TailscaleDiagnostic {
        isTestingTailscale = true
        latestTailscaleDiagnostic = .init(status: .checking, peer: nil, detail: "Testing an online peer…", checkedAt: Date())
        let result = await probe.tailscaleDiagnostic()
        latestTailscaleDiagnostic = result
        isTestingTailscale = false
        return result
    }
}
