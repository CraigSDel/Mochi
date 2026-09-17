import XCTest
@testable import LocalAIController

@MainActor
final class StartupValidationTests: XCTestCase {
    private func context() -> (URL, FakeProbe, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return (directory, probe, defaults)
    }

    func testMissingLlamaRuntimeCreatesLogFailureAndAlert() async throws {
        let (directory, probe, defaults) = context(); probe.commands["llama-server"] = nil
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.start(.llamaChat)
        let service = manager.services.first { $0.id == .llamaChat }
        XCTAssertEqual(service?.state, .failed)
        XCTAssertEqual(manager.presentedFailure?.guidance, "Run: brew install llama.cpp")
        let log = try String(contentsOf: directory.appendingPathComponent("llamaChat.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("llama-server is not installed"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.logURL(.llamaChat).path))
    }

    func testMissingOllamaHasInstallationGuidance() async {
        let (_, probe, defaults) = context(); probe.commands["ollama"] = nil
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.start(.ollama)
        XCTAssertEqual(manager.presentedFailure?.guidance, "Run: brew install ollama")
        XCTAssertTrue(manager.services.first { $0.id == .ollama }?.logText.contains("ollama is not installed") == true)
    }

    func testDisconnectedTailscaleIsLogged() async {
        let (_, probe, defaults) = context(); probe.tailnetIP = nil
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.start(.autocomplete)
        XCTAssertEqual(manager.services.first { $0.id == .autocomplete }?.state, .failed)
        XCTAssertTrue(manager.services.first { $0.id == .autocomplete }?.logText.contains("Tailscale is not connected") == true)
    }

    func testOccupiedPortLowDiskAndUnsafeMemoryAreObservable() async {
        do {
            let (_, probe, defaults) = context(); probe.occupiedPorts.insert(11435)
            let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false); await manager.start(.autocomplete)
            XCTAssertTrue(manager.presentedFailure?.message.contains("occupied") == true)
        }
        do {
            let (_, probe, defaults) = context(); probe.diskBytes = 1_000
            let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false); await manager.start(.embeddings)
            XCTAssertTrue(manager.presentedFailure?.message.contains("disk space") == true)
        }
        do {
            let (_, probe, defaults) = context(); probe.physicalMemory = 15 * 1_073_741_824
            let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false); await manager.start(.llamaChat)
            XCTAssertTrue(manager.presentedFailure?.message.contains("memory") == true)
        }
    }

    func testEarlyExitRemainsFailedAfterRefresh() async throws {
        let (directory, probe, defaults) = context()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("exit.sh")
        try "#!/bin/bash\necho runtime-boom\nexit 7\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.start(.llamaChat)
        try await Task.sleep(for: .milliseconds(200))
        await manager.refreshStatuses()
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .failed)
        XCTAssertTrue(manager.services.first { $0.id == .llamaChat }?.logText.contains("status=7") == true)
        XCTAssertNotNil(manager.presentedFailure)
    }

    func testDownloadModesProduceAuditableArguments() {
        let script = URL(fileURLWithPath: "/tmp/start.sh")
        let cached = ServiceLaunchConfiguration.defaultValue(for: .llamaChat)
        var downloads = cached; downloads.downloadPolicy = .allowDownloads
        XCTAssertTrue(ServiceManager.launchArguments(id: .llamaChat, script: script, modelChoice: "chat", configuration: cached).contains("--offline"))
        XCTAssertFalse(ServiceManager.launchArguments(id: .llamaChat, script: script, modelChoice: "chat", configuration: downloads).contains("--offline"))
        XCTAssertTrue(ServiceManager.launchArguments(id: .ollama, script: script, modelChoice: nil, configuration: .defaultValue(for: .ollama)).contains("--no-pull"))
        var ollama = ServiceLaunchConfiguration.defaultValue(for: .ollama); ollama.port = 12001; ollama.bindMode = .localhost
        let arguments = ServiceManager.launchArguments(id: .ollama, script: script, modelChoice: nil, configuration: ollama)
        XCTAssertTrue(arguments.contains("12001")); XCTAssertTrue(arguments.contains("localhost"))
    }

    func testLaunchEnvironmentIncludesSystemAdministrationPaths() {
        let environment = ServiceManager.launchEnvironment(id: .llamaChat, configuration: .defaultValue(for: .llamaChat), base: ["PATH": "/usr/bin:/bin", "PRESERVED": "yes"])
        let paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        XCTAssertTrue(paths.contains("/usr/sbin"))
        XCTAssertTrue(paths.contains("/sbin"))
        XCTAssertEqual(environment["PRESERVED"], "yes")
        XCTAssertEqual(environment["LLAMA_CHAT_REPO"], "unsloth/Qwen3.8-27B-GGUF")
        XCTAssertEqual(environment["LLAMA_CHAT_PORT"], "11437")
        let ollama = ServiceManager.launchEnvironment(id: .ollama, configuration: .defaultValue(for: .ollama), base: [:])
        XCTAssertEqual(ollama["OLLAMA_CHAT_MODEL"], "qwen3.8:27b")
        XCTAssertEqual(ollama["OLLAMA_NUM_PARALLEL"], "2")
    }

    func testLaunchEnvironmentContainsEveryConfiguredRuntimeValue() {
        var llama = ServiceLaunchConfiguration.defaultValue(for: .autocomplete)
        llama.port = 12002; llama.llama = .init(repository: "owner/repo", filename: "model.gguf", alias: "custom", contextSize: 4096, gpuLayers: 42)
        let llamaEnvironment = ServiceManager.launchEnvironment(id: .autocomplete, configuration: llama, base: [:])
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_PORT"], "12002")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_REPO"], "owner/repo")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_FILE"], "model.gguf")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_ALIAS"], "custom")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_CONTEXT"], "4096")
        XCTAssertEqual(llamaEnvironment["LLAMA_GPU_LAYERS"], "42")

        var ollama = ServiceLaunchConfiguration.defaultValue(for: .ollama)
        ollama.port = 12003; ollama.ollama = .init(chatModel: "chat:x", autocompleteModel: "code:x", embeddingModel: "embed:x", flashAttention: false, kvCacheType: "f16", contextLength: 2048, parallelRequests: 3, maxLoadedModels: 2)
        let ollamaEnvironment = ServiceManager.launchEnvironment(id: .ollama, configuration: ollama, base: [:])
        XCTAssertEqual(ollamaEnvironment["OLLAMA_PORT"], "12003")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_CHAT_MODEL"], "chat:x")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_AUTOCOMPLETE_MODEL"], "code:x")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_EMBEDDING_MODEL"], "embed:x")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_FLASH_ATTENTION"], "0")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_KV_CACHE_TYPE"], "f16")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_CONTEXT_LENGTH"], "2048")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_NUM_PARALLEL"], "3")
        XCTAssertEqual(ollamaEnvironment["OLLAMA_MAX_LOADED_MODELS"], "2")
    }

    func testLegacyManagedProcessRecordDecodesWithDefaultableBindMode() throws {
        let json = #"[{"serviceID":"llamaChat","pid":123,"port":11437,"expectedCommand":"start_llama_network.sh","startedAt":0,"logPath":"/tmp/test.log"}]"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let records = try decoder.decode([ManagedProcessRecord].self, from: Data(json.utf8))
        XCTAssertNil(records.first?.bindMode)
    }

    func testValidationAndStartAllPortCollision() {
        let (_, probe, defaults) = context(); let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        var chat = manager.configuration(for: .llamaChat); chat.port = 80; chat.llama?.repository = ""
        manager.updateConfiguration(chat, for: .llamaChat)
        XCTAssertTrue(manager.validationIssues(for: .llamaChat).contains { $0.field == "port" })
        XCTAssertTrue(manager.validationIssues(for: .llamaChat).contains { $0.field == "repository" })
        chat = .defaultValue(for: .llamaChat); chat.port = 11435; manager.updateConfiguration(chat, for: .llamaChat)
        XCTAssertTrue(manager.validationIssuesForStartAll().contains { $0.field == "ports" })
    }

    func testLanAndCustomModelsProduceConsolidatableWarnings() {
        let (_, probe, defaults) = context(); let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        var config = manager.configuration(for: .llamaChat); config.bindMode = .lan; config.llama?.repository = "custom/repo"
        manager.updateConfiguration(config, for: .llamaChat)
        let warnings = manager.launchWarnings(for: [.llamaChat])
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings.contains { $0.message.contains("unauthenticated") })
        XCTAssertTrue(warnings.contains { $0.message.contains("unverified") })
    }

    func testCustomModelRequiresAcknowledgementThenBypassesDefaultMemoryEstimate() async {
        let (_, probe, defaults) = context(); probe.physicalMemory = 1_000; probe.script = nil
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        var config = manager.configuration(for: .llamaChat); config.llama?.repository = "custom/repo"
        manager.updateConfiguration(config, for: .llamaChat)
        await manager.start(.llamaChat)
        XCTAssertEqual(manager.presentedFailure?.message, "Launch confirmation is required.")
        await manager.start(.llamaChat, warningsAcknowledged: true)
        XCTAssertEqual(manager.presentedFailure?.message, "Could not locate start_llama_network.sh.")
    }

    func testLocalhostLaunchDoesNotRequireTailscaleAndUsesLoopbackHealth() async throws {
        let (directory, probe, defaults) = context(); probe.commands["tailscale"] = nil; probe.tailnetIP = nil; probe.healthy = true
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory(); probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
        var config = manager.configuration(for: .llamaChat); config.bindMode = .localhost; manager.updateConfiguration(config, for: .llamaChat)
        await manager.start(.llamaChat)
        XCTAssertEqual(probe.lastHealthHost, "127.0.0.1")
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.endpoint, "http://127.0.0.1:11437/v1")
        await manager.stop(.llamaChat)
    }

    func testLanLaunchUsesLoopbackHealthAndLanDisplayEndpoint() async throws {
        let (directory, probe, defaults) = context(); probe.healthy = true
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory(); probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
        var config = manager.configuration(for: .llamaChat); config.bindMode = .lan; manager.updateConfiguration(config, for: .llamaChat)
        await manager.start(.llamaChat, warningsAcknowledged: true)
        XCTAssertEqual(probe.lastHealthHost, "127.0.0.1")
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.endpoint, "http://192.168.1.10:11437/v1")
        await manager.stop(.llamaChat)
    }
}