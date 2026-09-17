import Foundation
import Combine

@MainActor
final class ServiceManager: ObservableObject {
    @Published private(set) var services: [ServiceSnapshot]
    @Published var chatPort: Int {
        didSet { UserDefaults.standard.set(chatPort, forKey: "llamaChatPort") }
    }
    @Published var launchAtLogin = false
    @Published var generalMessage = ""

    private let fileManager = FileManager.default
    private var timer: Timer?
    private var processes: [ServiceID: Process] = [:]
    private let definitions: [ServiceDefinition] = [
        .init(id: .llamaChat, name: "Qwen Chat", detail: "Qwen3.8-27B chat and reasoning", runtime: "llama.cpp", defaultPort: 11437, modelChoice: "chat", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 17_000_000_000, supported: true, unavailableReason: nil),
        .init(id: .autocomplete, name: "Code Autocomplete", detail: "Qwen2.5-Coder-1.5B", runtime: "llama.cpp", defaultPort: 11435, modelChoice: "autocomplete", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 1_200_000_000, supported: true, unavailableReason: nil),
        .init(id: .embeddings, name: "Workspace Embeddings", detail: "Nomic Embed Text v1.5", runtime: "llama.cpp", defaultPort: 11436, modelChoice: "embedding", executable: "llama-server", modelFormat: "GGUF", estimatedBytes: 300_000_000, supported: true, unavailableReason: nil),
        .init(id: .ollama, name: "Ollama", detail: "Installed chat, coding, and embedding models", runtime: "Ollama", defaultPort: 11434, modelChoice: nil, executable: "ollama", modelFormat: "Ollama manifest", estimatedBytes: 20_000_000_000, supported: true, unavailableReason: nil)
    ]

    init() {
        let saved = UserDefaults.standard.integer(forKey: "llamaChatPort")
        chatPort = saved == 0 ? 11437 : saved
        services = definitions.map { ServiceSnapshot(definition: $0) }
        Task { await refreshStatuses() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshStatuses() }
        }
    }

    var hasManagedRunningServices: Bool {
        services.contains { $0.state == .running && $0.pid != nil }
    }

    func port(for id: ServiceID) -> Int? {
        id == .llamaChat ? chatPort : definitions.first(where: { $0.id == id })?.defaultPort
    }

    func startAll(allowDownloads: Bool = false) async {
        for id in [ServiceID.ollama, .llamaChat, .autocomplete, .embeddings] {
            await start(id, allowDownloads: allowDownloads)
        }
    }

    func stopAll() async {
        for id in [ServiceID.llamaChat, .autocomplete, .embeddings, .ollama] {
            await stop(id)
        }
    }

    func start(_ id: ServiceID, allowDownloads: Bool = false) async {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        let definition = services[index].definition
        guard definition.supported else {
            services[index].state = .unavailable
            services[index].statusText = definition.unavailableReason ?? "Unsupported"
            return
        }
        guard let port = port(for: id), ControllerPolicy.validPort(port) else {
            fail(index, "Port must be between 1024 and 65535.")
            return
        }
        guard !isPortListening(port) else {
            await refreshStatuses()
            if services[index].state != .external { fail(index, "Port \(port) is already occupied.") }
            return
        }
        guard commandPath(definition.executable ?? "") != nil else {
            fail(index, "\(definition.executable ?? definition.runtime) is not installed. Install it separately, then refresh.")
            return
        }
        guard (definition.runtime == "Ollama" || definition.modelFormat == "GGUF"),
              ControllerPolicy.fits(sizeBytes: definition.estimatedBytes) else {
            fail(index, "Model format or estimated memory use is not safe for this Mac.")
            return
        }
        guard commandPath("tailscale") != nil, tailscaleIP() != nil else {
            fail(index, "Tailscale is not connected. Connect it outside the app and retry.")
            return
        }
        guard hasMinimumFreeDisk() else {
            fail(index, "Less than 5 GB of free disk space is available.")
            return
        }

        let scriptName = id == .ollama ? "start_ollama_network.sh" : "start_llama_network.sh"
        guard let script = bundledScript(named: scriptName) else {
            fail(index, "Could not locate \(scriptName).")
            return
        }
        let paths = supportPaths()
        try? fileManager.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let logURL = paths.directory.appendingPathComponent("\(id.rawValue).log")
        fileManager.createFile(atPath: logURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            fail(index, "Could not open the service log.")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        if id == .ollama {
            process.arguments = [script.path, "--bind", "tailscale", "--no-install", "--no-tailscale-up"] + (allowDownloads ? [] : ["--no-pull"])
        } else {
            process.arguments = [script.path, "--model", definition.modelChoice!, "--bind", "tailscale", "--no-install", "--no-tailscale-up"] + (allowDownloads ? [] : ["--offline"])
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["LLAMA_CHAT_PORT"] = String(chatPort)
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self] _ in
            try? handle.close()
            Task { @MainActor in await self?.refreshStatuses() }
        }
        services[index].state = .starting
        services[index].statusText = "Starting…"
        do {
            try process.run()
            processes[id] = process
            let record = ManagedProcessRecord(serviceID: id, pid: process.processIdentifier, port: port, expectedCommand: scriptName, startedAt: Date(), logPath: logURL.path)
            save(record)
            services[index].pid = process.processIdentifier
            services[index].endpoint = endpoint(for: id, port: port)
            try? await Task.sleep(for: .seconds(1))
            await refreshStatuses()
        } catch {
            try? handle.close()
            fail(index, error.localizedDescription)
        }
    }

    func stop(_ id: ServiceID) async {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        guard let record = loadRecord(id), validate(record) else {
            if services[index].state == .external { services[index].statusText = "External process; not stopped for safety." }
            return
        }
        services[index].state = .stopping
        services[index].statusText = "Stopping…"
        kill(record.pid, SIGTERM)
        for _ in 0..<20 {
            if kill(record.pid, 0) != 0 { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        removeRecord(id)
        processes[id] = nil
        await refreshStatuses()
    }

    func refreshStatuses() async {
        for index in services.indices {
            let id = services[index].id
            if !services[index].definition.supported {
                services[index].state = .unavailable
                services[index].statusText = services[index].definition.unavailableReason ?? "Unsupported"
                continue
            }
            guard let port = port(for: id) else { continue }
            if let record = loadRecord(id), validate(record) {
                let listening = isPortListening(port)
                let healthy = listening ? await healthResponding(id, port: port) : false
                services[index].state = healthy ? .running : .starting
                services[index].statusText = healthy ? "Running and healthy" : "Process active; waiting for health"
                services[index].pid = record.pid
                services[index].endpoint = endpoint(for: id, port: port)
                services[index].logText = tail(record.logPath)
            } else if isPortListening(port) {
                removeRecord(id)
                services[index].state = .external
                services[index].statusText = "External service on port \(port)"
                services[index].pid = nil
                services[index].endpoint = endpoint(for: id, port: port)
            } else {
                removeRecord(id)
                services[index].state = .stopped
                services[index].statusText = "Stopped"
                services[index].pid = nil
                services[index].endpoint = nil
            }
        }
    }

    func clearLog(_ id: ServiceID) {
        let url = supportPaths().directory.appendingPathComponent("\(id.rawValue).log")
        try? Data().write(to: url)
        if let index = services.firstIndex(where: { $0.id == id }) { services[index].logText = "" }
    }

    func logURL(_ id: ServiceID) -> URL { supportPaths().directory.appendingPathComponent("\(id.rawValue).log") }

    private func fail(_ index: Int, _ message: String) {
        services[index].state = .failed
        services[index].statusText = message
    }

    private func endpoint(for id: ServiceID, port: Int) -> String {
        let host = tailscaleIP() ?? "127.0.0.1"
        return id == .ollama ? "http://\(host):\(port)" : "http://\(host):\(port)/v1"
    }

    private func commandPath(_ command: String) -> String? {
        guard !command.isEmpty else { return nil }
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return runAndCapture("/usr/bin/which", [command]).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func tailscaleIP() -> String? {
        guard let executable = commandPath("tailscale") else { return nil }
        return runAndCapture(executable, ["ip", "-4"])?.split(separator: "\n").first.map(String.init)
    }

    private func isPortListening(_ port: Int) -> Bool {
        guard let output = runAndCapture("/usr/sbin/lsof", ["-nP", "-tiTCP:\(port)", "-sTCP:LISTEN"]) else { return false }
        return !output.isEmpty
    }

    private func healthResponding(_ id: ServiceID, port: Int) async -> Bool {
        let host = tailscaleIP() ?? "127.0.0.1"
        let path = id == .ollama ? "/api/tags" : "/health"
        guard let url = URL(string: "http://\(host):\(port)\(path)") else { return false }
        var request = URLRequest(url: url); request.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            return (200..<500).contains(status)
        } catch { return false }
    }

    private func runAndCapture(_ executable: String, _ arguments: [String]) -> String? {
        guard fileManager.isExecutableFile(atPath: executable) else { return nil }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasMinimumFreeDisk() -> Bool {
        let values = try? supportPaths().directory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0) >= 5_000_000_000
    }

    private func bundledScript(named name: String) -> URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), fileManager.fileExists(atPath: url.path) { return url }
        let local = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(name)
        return fileManager.fileExists(atPath: local.path) ? local : nil
    }

    private func supportPaths() -> (directory: URL, records: URL) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Local AI Controller")
        return (base, base.appendingPathComponent("processes.json"))
    }

    private func allRecords() -> [ManagedProcessRecord] {
        guard let data = try? Data(contentsOf: supportPaths().records) else { return [] }
        return (try? JSONDecoder().decode([ManagedProcessRecord].self, from: data)) ?? []
    }

    private func loadRecord(_ id: ServiceID) -> ManagedProcessRecord? { allRecords().first { $0.serviceID == id } }
    private func save(_ record: ManagedProcessRecord) {
        var records = allRecords().filter { $0.serviceID != record.serviceID }; records.append(record)
        try? fileManager.createDirectory(at: supportPaths().directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: supportPaths().records, options: .atomic) }
    }
    private func removeRecord(_ id: ServiceID) {
        let records = allRecords().filter { $0.serviceID != id }
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: supportPaths().records, options: .atomic) }
    }
    private func validate(_ record: ManagedProcessRecord) -> Bool {
        guard kill(record.pid, 0) == 0 else { return false }
        let command = runAndCapture("/bin/ps", ["-p", String(record.pid), "-o", "command="]) ?? ""
        return command.contains(record.expectedCommand) || command.contains("llama-server") || (record.serviceID == .ollama && command.contains("bash"))
    }
    private func tail(_ path: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 64_000 ? size - 64_000 : 0)
        return String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
