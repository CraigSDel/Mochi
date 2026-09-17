import Foundation
import Combine

@MainActor
final class ServiceManager: ObservableObject {
    @Published private(set) var services: [ServiceSnapshot]
    @Published var presentedFailure: ServiceFailure?
    @Published var chatPort: Int { didSet { defaults.set(chatPort, forKey: "llamaChatPort") } }
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
    private let definitions: [ServiceDefinition] = [
        .init(id: .llamaChat, name: "Qwen Chat", detail: "Qwen3.8-27B chat and reasoning", runtime: "llama.cpp", defaultPort: 11437, modelChoice: "chat", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 17_000_000_000, supported: true, unavailableReason: nil),
        .init(id: .autocomplete, name: "Code Autocomplete", detail: "Qwen2.5-Coder-1.5B", runtime: "llama.cpp", defaultPort: 11435, modelChoice: "autocomplete", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 1_200_000_000, supported: true, unavailableReason: nil),
        .init(id: .embeddings, name: "Workspace Embeddings", detail: "Nomic Embed Text v1.5", runtime: "llama.cpp", defaultPort: 11436, modelChoice: "embedding", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 300_000_000, supported: true, unavailableReason: nil),
        .init(id: .ollama, name: "Ollama", detail: "Installed chat, coding, and embedding models", runtime: "Ollama", defaultPort: 11434, modelChoice: nil, executable: "ollama", modelFormat: "Ollama manifest", estimatedBytes: 20_000_000_000, supported: true, unavailableReason: nil)
    ]

    init(probe: (any SystemProbing)? = nil, processFactory: (any ProcessMaking)? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default, startTimer: Bool = true, stopPollAttempts: Int = 20) {
        self.fileManager = fileManager; self.defaults = defaults
        self.stopPollAttempts = stopPollAttempts
        self.probe = probe ?? LiveSystemProbe(fileManager: fileManager)
        self.processFactory = processFactory ?? LiveProcessFactory()
        let saved = defaults.integer(forKey: "llamaChatPort"); chatPort = saved == 0 ? 11437 : saved
        services = definitions.map { ServiceSnapshot(definition: $0) }
        try? fileManager.createDirectory(at: self.probe.supportDirectory, withIntermediateDirectories: true)
        for index in services.indices { ensureLog(services[index].id); services[index].logText = tail(logURL(services[index].id).path) }
        Task { await refreshStatuses() }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refreshStatuses() } } }
    }

    var hasManagedRunningServices: Bool {
        services.contains { service in
            service.pid != nil && [.starting, .running, .stopping].contains(service.state)
        }
    }
    func port(for id: ServiceID) -> Int? { id == .llamaChat ? chatPort : definitions.first(where: { $0.id == id })?.defaultPort }

    static func launchArguments(id: ServiceID, script: URL, modelChoice: String?, allowDownloads: Bool) -> [String] {
        if id == .ollama { return [script.path, "--bind", "tailscale", "--no-install", "--no-tailscale-up"] + (allowDownloads ? [] : ["--no-pull"]) }
        return [script.path, "--model", modelChoice!, "--bind", "tailscale", "--no-install", "--no-tailscale-up"] + (allowDownloads ? [] : ["--offline"])
    }

    func startAll(allowDownloads: Bool = false) async { for id in [ServiceID.ollama, .llamaChat, .autocomplete, .embeddings] { await start(id, allowDownloads: allowDownloads) } }
    func stopAll() async { for id in [ServiceID.llamaChat, .autocomplete, .embeddings, .ollama] { await stop(id) } }

    func start(_ id: ServiceID, allowDownloads: Bool = false) async {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        let definition = services[index].definition
        ensureLog(id); append(id, "========== START ATTEMPT =========="); append(id, "Mode: \(allowDownloads ? "downloads explicitly allowed" : "cached models only")")
        services[index].state = .starting; services[index].statusText = "Running preflight checks…"; presentedFailure = nil

        guard let port = port(for: id), ControllerPolicy.validPort(port) else { fail(index, "Port must be between 1024 and 65535.", "Choose a valid port in Settings."); return }
        let occupied = probe.isPortListening(port); append(id, "Port \(port): \(occupied ? "occupied" : "available")")
        guard !occupied else { fail(index, "Port \(port) is already occupied.", "Stop the external service or choose another chat port."); return }
        guard let executable = probe.commandPath(definition.executable ?? "") else {
            fail(index, "\(definition.executable ?? definition.runtime) is not installed.", "Run: brew install \(id == .ollama ? "ollama" : "llama.cpp")"); return
        }
        append(id, "Runtime executable: \(executable)")
        let safe = (definition.runtime == "Ollama" || definition.modelFormat == "GGUF") && ControllerPolicy.fits(sizeBytes: definition.estimatedBytes, physicalMemory: probe.physicalMemory)
        append(id, "Model format: \(definition.modelFormat); estimated size: \(definition.estimatedBytes ?? 0) bytes; memory fit: \(safe)")
        guard safe else { fail(index, "Model format or estimated memory use is not safe for this Mac.", "Choose a smaller compatible model."); return }
        guard let tailscale = probe.commandPath("tailscale") else { fail(index, "Tailscale is not installed.", "Run: brew install tailscale"); return }
        append(id, "Tailscale executable: \(tailscale)")
        guard let host = probe.tailscaleIP() else { fail(index, "Tailscale is not connected.", "Connect Tailscale outside the app, then retry."); return }
        append(id, "Tailscale IPv4: \(host)")
        let disk = probe.availableDiskBytes(); append(id, "Available disk: \(disk) bytes")
        guard disk >= 5_000_000_000 else { fail(index, "Less than 5 GB of free disk space is available.", "Free disk space, then retry."); return }
        let scriptName = id == .ollama ? "start_ollama_network.sh" : "start_llama_network.sh"
        guard let script = probe.scriptURL(named: scriptName) else { fail(index, "Could not locate \(scriptName).", "Rebuild the app so launcher resources are bundled."); return }

        let handle: FileHandle
        do { handle = try FileHandle(forWritingTo: logURL(id)); try handle.seekToEnd() } catch { fail(index, "Could not open the service log.", error.localizedDescription); return }
        outputHandles[id] = handle
        let process = processFactory.makeProcess(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = Self.launchArguments(id: id, script: script, modelChoice: definition.modelChoice, allowDownloads: allowDownloads)
        var environment = ProcessInfo.processInfo.environment; environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"; environment["LLAMA_CHAT_PORT"] = String(chatPort)
        process.environment = environment; process.standardOutput = handle; process.standardError = handle
        append(id, "Launcher: /bin/bash \(process.arguments?.joined(separator: " ") ?? "")")
        process.terminationHandler = { [weak self] ended in
            Task { @MainActor in self?.handleTermination(id, status: ended.terminationStatus, reason: ended.terminationReason) }
        }
        do {
            try process.run(); processes[id] = process; append(id, "Process started with PID \(process.processIdentifier)")
            save(.init(serviceID: id, pid: process.processIdentifier, port: port, expectedCommand: scriptName, startedAt: Date(), logPath: logURL(id).path))
            services[index].pid = process.processIdentifier; services[index].endpoint = endpoint(id, port, host)
            try? await Task.sleep(for: .seconds(1)); await refreshStatuses()
        } catch {
            outputHandles[id] = nil
            try? handle.close()
            fail(index, "Failed to launch the service.", error.localizedDescription)
        }
    }

    func stop(_ id: ServiceID) async {
        guard let index = services.firstIndex(where: { $0.id == id }), let record = loadRecord(id), validate(record) else {
            if let index = services.firstIndex(where: { $0.id == id }), services[index].state == .external { services[index].statusText = "External process; not stopped for safety." }; return
        }
        let hasLocalTerminationHandler = processes[id] != nil
        stopRequested.insert(id)
        services[index].state = .stopping; services[index].statusText = "Stopping…"; append(id, "Stop requested"); kill(record.pid, SIGTERM)
        for _ in 0..<stopPollAttempts { if !probe.isProcessRunning(record.pid) { break }; try? await Task.sleep(for: .milliseconds(250)) }
        if probe.isProcessRunning(record.pid) {
            services[index].state = .running
            services[index].statusText = "Stop timed out; process is still running"
            services[index].pid = record.pid
            append(id, "ERROR: Process did not stop after SIGTERM; ownership retained")
            return
        }
        if !hasLocalTerminationHandler { completeIntentionalStop(id) }
        await refreshStatuses()
    }

    func refreshStatuses() async {
        for index in services.indices {
            let id = services[index].id; services[index].logText = tail(logURL(id).path)
            if let record = loadRecord(id), validate(record) {
                let port = record.port
                let listening = probe.isPortListening(port), host = probe.tailscaleIP() ?? "127.0.0.1"
                let healthy = listening ? await probe.healthResponding(id, port: port, host: host) : false
                services[index].state = healthy ? .running : .starting; services[index].statusText = healthy ? "Running and healthy" : "Process active; waiting for health"
                services[index].pid = record.pid; services[index].endpoint = endpoint(id, port, host)
            } else if let port = port(for: id), probe.isPortListening(port) {
                let host = probe.tailscaleIP() ?? "127.0.0.1"
                removeRecord(id); services[index].state = .external; services[index].statusText = "External service on port \(port)"; services[index].pid = nil; services[index].endpoint = endpoint(id, port, host)
            } else if services[index].state != .failed {
                removeRecord(id); services[index].state = .stopped; services[index].statusText = "Stopped"; services[index].pid = nil; services[index].endpoint = nil
            }
        }
    }

    func clearLog(_ id: ServiceID) {
        if let handle = outputHandles[id] {
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
        } else {
            try? Data().write(to: logURL(id))
        }
        if let i = services.firstIndex(where: { $0.id == id }) { services[i].logText = "" }
    }
    func logURL(_ id: ServiceID) -> URL { probe.supportDirectory.appendingPathComponent("\(id.rawValue).log") }
    private func ensureLog(_ id: ServiceID) { try? fileManager.createDirectory(at: probe.supportDirectory, withIntermediateDirectories: true); if !fileManager.fileExists(atPath: logURL(id).path) { fileManager.createFile(atPath: logURL(id).path, contents: nil) } }
    private func append(_ id: ServiceID, _ message: String) {
        ensureLog(id); let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let handle = outputHandles[id] {
            try? handle.write(contentsOf: Data(line.utf8))
        } else if let handle = try? FileHandle(forWritingTo: logURL(id)) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
        }
        if let i = services.firstIndex(where: { $0.id == id }) { services[i].logText = tail(logURL(id).path) }
    }
    private func fail(_ index: Int, _ message: String, _ guidance: String) {
        let id = services[index].id; append(id, "ERROR: \(message) Guidance: \(guidance)"); services[index].state = .failed; services[index].statusText = message; services[index].pid = nil
        presentedFailure = .init(serviceID: id, serviceName: services[index].definition.name, message: message, guidance: guidance, timestamp: Date(), logURL: logURL(id))
    }
    private func handleTermination(_ id: ServiceID, status: Int32, reason: Process.TerminationReason) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        append(id, "Process terminated; status=\(status), reason=\(reason.rawValue)")
        if let handle = outputHandles.removeValue(forKey: id) { try? handle.close() }
        processes[id] = nil
        if stopRequested.contains(id) || services[index].state == .stopping {
            completeIntentionalStop(id)
        } else {
            removeRecord(id)
            fail(index, "Service exited unexpectedly (status \(status)).", "Review the log for the runtime error.")
        }
    }
    private func completeIntentionalStop(_ id: ServiceID) {
        stopRequested.remove(id); removeRecord(id); processes[id] = nil
        if let index = services.firstIndex(where: { $0.id == id }) {
            services[index].state = .stopped; services[index].statusText = "Stopped"; services[index].pid = nil; services[index].endpoint = nil
        }
    }
    private func endpoint(_ id: ServiceID, _ port: Int, _ host: String) -> String { id == .ollama ? "http://\(host):\(port)" : "http://\(host):\(port)/v1" }
    private func recordsURL() -> URL { probe.supportDirectory.appendingPathComponent("processes.json") }
    private func allRecords() -> [ManagedProcessRecord] { (try? Data(contentsOf: recordsURL())).flatMap { try? JSONDecoder().decode([ManagedProcessRecord].self, from: $0) } ?? [] }
    private func loadRecord(_ id: ServiceID) -> ManagedProcessRecord? { allRecords().first { $0.serviceID == id } }
    private func save(_ record: ManagedProcessRecord) { var r = allRecords().filter { $0.serviceID != record.serviceID }; r.append(record); if let d = try? JSONEncoder().encode(r) { try? d.write(to: recordsURL(), options: .atomic) } }
    private func removeRecord(_ id: ServiceID) { if let d = try? JSONEncoder().encode(allRecords().filter { $0.serviceID != id }) { try? d.write(to: recordsURL(), options: .atomic) } }
    private func validate(_ record: ManagedProcessRecord) -> Bool { probe.isProcessRunning(record.pid) && { let c = probe.processCommand(record.pid); return c.contains(record.expectedCommand) || c.contains("llama-server") || (record.serviceID == .ollama && c.contains("bash")) }() }
    private func tail(_ path: String) -> String { guard let h = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }; defer { try? h.close() }; let s = (try? h.seekToEnd()) ?? 0; try? h.seek(toOffset: s > 64_000 ? s - 64_000 : 0); return String(data: h.readDataToEndOfFile(), encoding: .utf8) ?? "" }
}
