import Foundation
import Combine
@MainActor
final class ServiceManager: ObservableObject {
    static let startAllServiceIDs: [ServiceID] = [.llamaChat, .autocomplete, .embeddings]
    @Published private(set) var services: [ServiceSnapshot]
    @Published private(set) var configurations: [ServiceID: ServiceLaunchConfiguration]
    @Published private(set) var installedModels: [DiscoveredModel]
    @Published private(set) var latestTailscaleDiagnostic: TailscaleDiagnostic?
    @Published private(set) var isTestingTailscale = false
    @Published var presentedFailure: ServiceFailure?
    @Published var launchAtLogin = false
    private let fileManager: FileManager
    private let probe: any SystemProbing
    private let processFactory: any ProcessMaking
    private let defaults: UserDefaults
    private let stopPollAttempts: Int
    private var timer: Timer?
    private var processes: [ServiceID: Process] = [:]
    private var outputHandles: [ServiceID: FileHandle] = [:]
    private var stopRequested: Set<ServiceID> = []
    private var recommendationMetadata: [ModelRecommendation] = []
    private static let configurationKey = "serviceLaunchConfigurations.v1"
    private let definitions: [ServiceDefinition] = [
        .init(id: .llamaChat, name: "Qwen Chat", detail: "Qwen3.8-27B chat and reasoning", runtime: "llama.cpp", defaultPort: 11437, modelChoice: "chat", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 17_000_000_000, supported: true, unavailableReason: nil),
        .init(id: .autocomplete, name: "Code Autocomplete", detail: "Qwen2.5-Coder-1.5B", runtime: "llama.cpp", defaultPort: 11435, modelChoice: "autocomplete", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 1_200_000_000, supported: true, unavailableReason: nil),
        .init(id: .embeddings, name: "Workspace Embeddings", detail: "Nomic Embed Text v1.5", runtime: "llama.cpp", defaultPort: 11436, modelChoice: "embedding", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 300_000_000, supported: true, unavailableReason: nil),
        .init(id: .ollama, name: "Ollama", detail: "Installed chat, coding, and embedding models", runtime: "Ollama", defaultPort: 11434, modelChoice: nil, executable: "ollama", modelFormat: "Ollama manifest", estimatedBytes: 17_000_000_000, supported: true, unavailableReason: nil)
    ]
    init(probe: (any SystemProbing)? = nil, processFactory: (any ProcessMaking)? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default, startTimer: Bool = true, stopPollAttempts: Int = 20) {
        self.fileManager = fileManager; self.defaults = defaults; self.stopPollAttempts = stopPollAttempts
        let resolvedProbe = probe ?? LiveSystemProbe(fileManager: fileManager)
        self.probe = resolvedProbe; self.processFactory = processFactory ?? LiveProcessFactory()
        self.installedModels = resolvedProbe.discoverModels()
        var loaded = Self.loadConfigurations(from: defaults)
        if loaded == nil {
            var initial = Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { ($0, ServiceLaunchConfiguration.defaultValue(for: $0)) })
            let legacyPort = defaults.integer(forKey: "llamaChatPort")
            if legacyPort != 0 { initial[.llamaChat]?.port = legacyPort }
            loaded = initial
        }
        var resolvedConfigurations = loaded ?? [:]
        for id in ServiceID.allCases where resolvedConfigurations[id] == nil { resolvedConfigurations[id] = .defaultValue(for: id) }
        for id in ServiceID.allCases {
            if let context = resolvedConfigurations[id]?.llama?.contextSize { resolvedConfigurations[id]?.llama?.contextSize = ContextSizeOptions.normalized(context) }
            else if let context = resolvedConfigurations[id]?.ollama?.contextLength { resolvedConfigurations[id]?.ollama?.contextLength = ContextSizeOptions.normalized(context) }
        }
        configurations = resolvedConfigurations
        services = definitions.map { ServiceSnapshot(definition: $0) }
        persistConfigurations()
        try? fileManager.createDirectory(at: self.probe.supportDirectory, withIntermediateDirectories: true)
        for index in services.indices { ensureLog(services[index].id); services[index].logText = tail(logURL(services[index].id).path) }
        Task { await refreshStatuses() }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refreshStatuses() } } }
    }
    var hasManagedRunningServices: Bool { services.contains { $0.pid != nil && [.starting, .running, .stopping].contains($0.state) } }
    var managedProcessIDs: [ServiceID: Int32] { ManagedProcessOwnership.processIDs(from: managedProcessMemoryRoots) }
    var managedProcessMemoryRoots: [ServiceID: ManagedProcessRoot] { ManagedProcessOwnership.roots(records: allRecords(), probe: probe) }
    func configuration(for id: ServiceID) -> ServiceLaunchConfiguration { configurations[id] ?? .defaultValue(for: id) }
    func isConfigurationLocked(_ id: ServiceID) -> Bool { services.first(where: { $0.id == id }).map { [.starting, .running, .stopping].contains($0.state) } ?? false }
    func updateConfiguration(_ configuration: ServiceLaunchConfiguration, for id: ServiceID) { guard !isConfigurationLocked(id) else { return }; configurations[id] = configuration; persistConfigurations() }
    func resetConfiguration(_ id: ServiceID) { updateConfiguration(.defaultValue(for: id), for: id) }
    func port(for id: ServiceID) -> Int? { configurations[id]?.port }
    func wifiIP() -> String? { probe.wifiIP() }
    func localNetworkIP() -> String? { probe.wifiIP() ?? probe.localNetworkIP() }
    func refreshModelInventory() { installedModels = probe.discoverModels() }
    func updateRecommendationMetadata(_ recommendations: [ModelRecommendation]) { recommendationMetadata = recommendations }
    func memoryAssessment(for id: ServiceID) -> MemoryAssessment {
        let config = configuration(for: id)
        if let llama = config.llama {
            return ControllerPolicy.memoryAssessment(modelBytes: llamaModelSize(llama, serviceID: id).map { [$0] }, contextSize: llama.contextSize, physicalMemory: probe.physicalMemory)
        }
        guard let ollama = config.ollama else { return ControllerPolicy.memoryAssessment(modelBytes: nil, contextSize: 0, physicalMemory: probe.physicalMemory) }
        let selection = OllamaMemoryModelSelection.resolve(
            configuration: ollama,
            installedModels: installedModels,
            recommendations: recommendationMetadata,
            isDefaultConfiguration: config == .defaultValue(for: .ollama),
            defaultSize: definition(for: id)?.estimatedBytes
        )
        return ControllerPolicy.memoryAssessment(modelBytes: selection.modelBytes, contextSize: ollama.contextLength, parallelRequests: ollama.parallelRequests, loadedModelCount: selection.loadedModelCount, physicalMemory: probe.physicalMemory)
    }
    func performanceGuidance() -> [PerformanceGuidance] {
        PerformanceGuidanceBuilder.make(
            configurations: configurations, installedModels: installedModels,
            recommendations: recommendationMetadata, physicalMemory: probe.physicalMemory,
            defaultLlamaConfiguration: ServiceLaunchConfiguration.defaultValue(for: .llamaChat).llama, defaultLlamaSize: definition(for: .llamaChat)?.estimatedBytes,
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
        // Compared by normalized reference: the catalog publishes `llava` and a
        // local inventory reports `llava:latest`, and Ollama resolves both.
        let installedKeys = Set(installedModels.filter { $0.runtime == .ollama }.map { OllamaModelReference.key($0.name) })
        return [ollama.chatModel, ollama.autocompleteModel, ollama.embeddingModel].filter { !installedKeys.contains(OllamaModelReference.key($0)) }
    }

    func validationIssues(for id: ServiceID) -> [ConfigurationIssue] {
        let config = configuration(for: id); var issues: [ConfigurationIssue] = []
        if !ControllerPolicy.validPort(config.port) { issues.append(.init(field: "port", message: "Port must be between 1024 and 65535.")) }
        if let llama = config.llama {
            for (field, value, label) in [("repository", llama.repository, "Repository"), ("filename", llama.filename, "GGUF filename"), ("alias", llama.alias, "Model alias")] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.init(field: field, message: "\(label) is required.")) }
            if llama.contextSize <= 0 { issues.append(.init(field: "contextSize", message: "Context size must be greater than zero.")) }
            if llama.gpuLayers < 0 { issues.append(.init(field: "gpuLayers", message: "GPU layers cannot be negative.")) }
        } else if let ollama = config.ollama {
            for (field, value, label) in [("chatModel", ollama.chatModel, "Chat model"), ("autocompleteModel", ollama.autocompleteModel, "Autocomplete model"), ("embeddingModel", ollama.embeddingModel, "Embedding model"), ("kvCacheType", ollama.kvCacheType, "KV cache type")] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.init(field: field, message: "\(label) is required.")) }
            if ollama.contextLength <= 0 { issues.append(.init(field: "contextLength", message: "Context length must be greater than zero.")) }
            if ollama.parallelRequests <= 0 { issues.append(.init(field: "parallelRequests", message: "Parallel requests must be greater than zero.")) }
            if ollama.maxLoadedModels <= 0 { issues.append(.init(field: "maxLoadedModels", message: "Maximum loaded models must be greater than zero.")) }
        } else { issues.append(.init(field: "runtime", message: "Runtime configuration is missing.")) }
        return issues
    }

    func validationIssuesForStartAll() -> [ConfigurationIssue] {
        let ids = Self.startAllServiceIDs
        var issues: [ConfigurationIssue] = ids.flatMap { id in validationIssues(for: id).map { ConfigurationIssue(field: "\(id.rawValue).\($0.field)", message: "\(serviceName(id)): \($0.message)") } }
        for (port, conflictingIDs) in Dictionary(grouping: ids, by: { configuration(for: $0).port }) where conflictingIDs.count > 1 { issues.append(.init(field: "ports", message: "Port \(port) is assigned to \(conflictingIDs.map(serviceName).joined(separator: ", ")).")) }
        return issues
    }

    func launchWarnings(for ids: [ServiceID], bindModeOverride: BindMode? = nil) -> [LaunchWarning] {
        ids.flatMap { id -> [LaunchWarning] in
            let config = configuration(for: id); var warnings: [LaunchWarning] = []
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

    func startAll(warningsAcknowledged: Bool = false, bindModeOverride: BindMode? = nil) async {
        let ids = Self.startAllServiceIDs
        guard validationIssuesForStartAll().isEmpty,
              warningsAcknowledged || launchWarnings(for: ids, bindModeOverride: bindModeOverride).isEmpty else { return }
        for id in ids {
            await start(
                id,
                warningsAcknowledged: warningsAcknowledged,
                bindModeOverride: bindModeOverride,
                overrideSavedMode: true
            )
        }
    }
    func stopAll() async { for id in [ServiceID.llamaChat, .autocomplete, .embeddings, .ollama] { await stop(id) } }

    func start(
        _ id: ServiceID,
        warningsAcknowledged: Bool = false,
        bindModeOverride: BindMode? = nil,
        overrideSavedMode: Bool = false
    ) async {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        let definition = services[index].definition, savedConfig = configuration(for: id)
        var config = savedConfig
        config.bindMode = Self.effectiveBindMode(
            configured: savedConfig.bindMode,
            override: bindModeOverride,
            overrideSavedMode: overrideSavedMode
        )
        guard validationIssues(for: id).isEmpty else { fail(index, "Launch configuration is invalid.", "Correct the highlighted fields and retry."); return }
        guard warningsAcknowledged || launchWarnings(for: [id]).isEmpty else { fail(index, "Launch confirmation is required.", "Review and acknowledge the network or custom-model warning."); return }
        ensureLog(id); append(id, "========== START ATTEMPT ==========")
        let overrideNote = config.bindMode != savedConfig.bindMode ? " (one-time override from \(savedConfig.bindMode.title))" : ""
        append(id, "Mode: \(config.downloadPolicy.title); bind: \(config.bindMode.title)\(overrideNote); port: \(config.port)")
        services[index].state = .starting; services[index].statusText = "Running preflight checks…"; presentedFailure = nil
        let occupied = probe.isPortListening(config.port); append(id, "Port \(config.port): \(occupied ? "occupied" : "available")")
        guard !occupied else { fail(index, "Port \(config.port) is already occupied.", "Stop the external service or choose another port."); return }
        guard let executable = probe.commandPath(definition.executable ?? "") else { fail(index, "\(definition.executable ?? definition.runtime) is not installed.", "Run: brew install \(id == .ollama ? "ollama" : "llama.cpp")"); return }
        append(id, "Runtime executable: \(executable)")
        let assessment = memoryAssessment(for: id)
        append(id, "Memory assessment: \(assessment.severity.rawValue); \(assessment.message)")
        if config.bindMode == .tailscale {
            guard probe.commandPath("tailscale") != nil else { fail(index, "Tailscale is not installed.", "Run: brew install tailscale"); return }
            guard probe.tailscaleIP() != nil else { fail(index, "Tailscale is not connected.", "Connect Tailscale outside the app, then retry."); return }
        }
        guard let hosts = resolvedHosts(for: config.bindMode) else {
            let message = config.bindMode == .tailscale ? "Tailscale is not installed or connected." : "A local network IPv4 address could not be resolved."
            let guidance = config.bindMode == .tailscale ? "Install and connect Tailscale, then retry." : "Connect this Mac to a local network, then retry."
            fail(index, message, guidance); return
        }
        append(id, "Endpoint host: \(hosts.display); health host: \(hosts.health)")
        let disk = probe.availableDiskBytes(); append(id, "Available disk: \(disk) bytes")
        guard disk >= 5_000_000_000 else { fail(index, "Less than 5 GB of free disk space is available.", "Free disk space, then retry."); return }
        let scriptName = id == .ollama ? "start_ollama_network.sh" : "start_llama_network.sh"
        guard let script = probe.scriptURL(named: scriptName) else { fail(index, "Could not locate \(scriptName).", "Rebuild the app so launcher resources are bundled."); return }
        let handle: FileHandle
        do { handle = try FileHandle(forWritingTo: logURL(id)); try handle.seekToEnd() } catch { fail(index, "Could not open the service log.", error.localizedDescription); return }
        outputHandles[id] = handle
        let process = processFactory.makeProcess(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = LaunchInvocation.arguments(id: id, script: script, modelChoice: definition.modelChoice, configuration: config); process.environment = LaunchInvocation.environment(id: id, configuration: config)
        process.standardOutput = handle; process.standardError = handle
        append(id, "Launcher: /bin/bash \(process.arguments?.joined(separator: " ") ?? "")")
        process.terminationHandler = { [weak self] ended in Task { @MainActor in self?.handleTermination(id, status: ended.terminationStatus, reason: ended.terminationReason) } }
        do {
            try process.run(); processes[id] = process; append(id, "Process started with PID \(process.processIdentifier)")
            save(.init(serviceID: id, pid: process.processIdentifier, port: config.port, expectedCommand: scriptName, startedAt: Date(), logPath: logURL(id).path, bindMode: config.bindMode))
            services[index].pid = process.processIdentifier; services[index].endpoint = Self.endpoint(id, config.port, hosts.display)
            try? await Task.sleep(for: .seconds(1)); await refreshStatuses()
        } catch { outputHandles[id] = nil; try? handle.close(); fail(index, "Failed to launch the service.", error.localizedDescription) }
    }

    func stop(_ id: ServiceID) async {
        guard let index = services.firstIndex(where: { $0.id == id }), let record = loadRecord(id), validate(record) else { if let index = services.firstIndex(where: { $0.id == id }), services[index].state == .external { services[index].statusText = "External process; not stopped for safety." }; return }
        let hasLocalTerminationHandler = processes[id] != nil; stopRequested.insert(id); services[index].state = .stopping; services[index].statusText = "Stopping…"; append(id, "Stop requested"); kill(record.pid, SIGTERM)
        for _ in 0..<stopPollAttempts { if !probe.isProcessRunning(record.pid) { break }; try? await Task.sleep(for: .milliseconds(250)) }
        if probe.isProcessRunning(record.pid) { services[index].state = .running; services[index].statusText = "Stop timed out; process is still running"; services[index].pid = record.pid; append(id, "ERROR: Process did not stop after SIGTERM; ownership retained"); return }
        if !hasLocalTerminationHandler { completeIntentionalStop(id) }; await refreshStatuses()
    }

    func refreshStatuses() async {
        for index in services.indices {
            let id = services[index].id; services[index].logText = tail(logURL(id).path)
            if let record = loadRecord(id), validate(record) {
                let wasRunning = services[index].state == .running
                let hosts = resolvedHosts(for: record.bindMode ?? .tailscale) ?? ("127.0.0.1", "127.0.0.1")
                let listening = probe.isPortListening(record.port), healthy = listening ? await probe.healthResponding(id, port: record.port, host: hosts.health) : false
                let availableEndpoint = Self.endpoint(id, record.port, hosts.display)
                services[index].state = healthy ? .running : .starting; services[index].statusText = healthy ? "Running and healthy at \(availableEndpoint)" : "Process active; waiting for health"; services[index].pid = record.pid; services[index].endpoint = availableEndpoint
                if healthy && !wasRunning { append(id, "Model available at \(availableEndpoint)") }
            } else {
                let config = configuration(for: id)
                if probe.isPortListening(config.port) {
                    let hosts = resolvedHosts(for: config.bindMode) ?? ("127.0.0.1", "127.0.0.1")
                    removeRecord(id); services[index].state = .external; services[index].statusText = "External service on port \(config.port)"; services[index].pid = nil; services[index].endpoint = Self.endpoint(id, config.port, hosts.display)
                } else if services[index].state != .failed { removeRecord(id); services[index].state = .stopped; services[index].statusText = "Stopped"; services[index].pid = nil; services[index].endpoint = nil }
            }
        }
    }

    func clearLog(_ id: ServiceID) { if let h = outputHandles[id] { try? h.truncate(atOffset: 0); try? h.seek(toOffset: 0) } else { try? Data().write(to: logURL(id)) }; if let i = services.firstIndex(where: { $0.id == id }) { services[i].logText = "" } }
    func logURL(_ id: ServiceID) -> URL { probe.supportDirectory.appendingPathComponent("\(id.rawValue).log") }
    private func resolvedHosts(for bind: BindMode) -> (display: String, health: String)? { switch bind { case .tailscale: guard probe.commandPath("tailscale") != nil, let ip = probe.tailscaleIP() else { return nil }; return (ip, ip); case .localhost: return ("127.0.0.1", "127.0.0.1"); case .lan: guard let ip = probe.wifiIP() ?? probe.localNetworkIP() else { return nil }; return (ip, "127.0.0.1") } }
    private func serviceName(_ id: ServiceID) -> String { definitions.first(where: { $0.id == id })?.name ?? id.rawValue }
    private func definition(for id: ServiceID) -> ServiceDefinition? { definitions.first { $0.id == id } }
    private func llamaModelSize(_ llama: LlamaLaunchConfiguration, serviceID: ServiceID) -> Int64? {
        if let size = installedModels.first(where: { $0.runtime == .llamaCpp && $0.repository == llama.repository && $0.filename == llama.filename })?.sizeBytes { return size }
        if let size = recommendationMetadata.first(where: { $0.repository == llama.repository && $0.filename == llama.filename })?.sizeBytes { return size }
        let defaults = ServiceLaunchConfiguration.defaultValue(for: serviceID).llama
        return defaults?.repository == llama.repository && defaults?.filename == llama.filename ? definition(for: serviceID)?.estimatedBytes : nil
    }
    private static func loadConfigurations(from defaults: UserDefaults) -> [ServiceID: ServiceLaunchConfiguration]? { guard let data = defaults.data(forKey: configurationKey), let stored = try? JSONDecoder().decode([String: ServiceLaunchConfiguration].self, from: data) else { return nil }; return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in ServiceID(rawValue: key).map { ($0, value) } }) }
    private func persistConfigurations() { let stored = Dictionary(uniqueKeysWithValues: configurations.map { ($0.key.rawValue, $0.value) }); if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.configurationKey) } }
    private func ensureLog(_ id: ServiceID) { try? fileManager.createDirectory(at: probe.supportDirectory, withIntermediateDirectories: true); if !fileManager.fileExists(atPath: logURL(id).path) { fileManager.createFile(atPath: logURL(id).path, contents: nil) } }
    private func append(_ id: ServiceID, _ message: String) { ensureLog(id); let data = Data("[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n".utf8); if let h = outputHandles[id] { try? h.write(contentsOf: data) } else if let h = try? FileHandle(forWritingTo: logURL(id)) { _ = try? h.seekToEnd(); try? h.write(contentsOf: data); try? h.close() }; if let i = services.firstIndex(where: { $0.id == id }) { services[i].logText = tail(logURL(id).path) } }
    private func fail(_ index: Int, _ message: String, _ guidance: String) { let id = services[index].id; append(id, "ERROR: \(message) Guidance: \(guidance)"); services[index].state = .failed; services[index].statusText = message; services[index].pid = nil; presentedFailure = .init(serviceID: id, serviceName: services[index].definition.name, message: message, guidance: guidance, timestamp: Date(), logURL: logURL(id)) }
    private func handleTermination(_ id: ServiceID, status: Int32, reason: Process.TerminationReason) { guard let index = services.firstIndex(where: { $0.id == id }) else { return }; append(id, "Process terminated; status=\(status), reason=\(reason.rawValue)"); if let h = outputHandles.removeValue(forKey: id) { try? h.close() }; processes[id] = nil; if stopRequested.contains(id) || services[index].state == .stopping { completeIntentionalStop(id) } else { removeRecord(id); fail(index, "Service exited unexpectedly (status \(status)).", "Review the log for the runtime error.") } }
    private func completeIntentionalStop(_ id: ServiceID) { stopRequested.remove(id); removeRecord(id); processes[id] = nil; if let index = services.firstIndex(where: { $0.id == id }) { services[index].state = .stopped; services[index].statusText = "Stopped"; services[index].pid = nil; services[index].endpoint = nil } }
    static func endpoint(_ id: ServiceID, _ port: Int, _ host: String) -> String { id == .ollama ? "http://\(host):\(port)" : "http://\(host):\(port)/v1" }
    private func recordsURL() -> URL { probe.supportDirectory.appendingPathComponent("processes.json") }
    private func allRecords() -> [ManagedProcessRecord] { (try? Data(contentsOf: recordsURL())).flatMap { try? JSONDecoder().decode([ManagedProcessRecord].self, from: $0) } ?? [] }
    private func loadRecord(_ id: ServiceID) -> ManagedProcessRecord? { allRecords().first { $0.serviceID == id } }
    private func save(_ record: ManagedProcessRecord) { var records = allRecords().filter { $0.serviceID != record.serviceID }; records.append(record); if let data = try? JSONEncoder().encode(records) { try? data.write(to: recordsURL(), options: .atomic) } }
    private func removeRecord(_ id: ServiceID) { if let data = try? JSONEncoder().encode(allRecords().filter { $0.serviceID != id }) { try? data.write(to: recordsURL(), options: .atomic) } }
    private func validate(_ record: ManagedProcessRecord) -> Bool { if case .owned = ManagedProcessOwnership.root(record, probe: probe) { return true }; return false }
    private func tail(_ path: String) -> String { guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }; defer { try? handle.close() }; let size = (try? handle.seekToEnd()) ?? 0; try? handle.seek(toOffset: size > 64_000 ? size - 64_000 : 0); return String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? "" }
}
