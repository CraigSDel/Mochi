import XCTest
@testable import LocalAIController

final class ControllerPolicyTests: XCTestCase {
    func testPortValidation() {
        XCTAssertTrue(ControllerPolicy.validPort(11437))
        XCTAssertFalse(ControllerPolicy.validPort(80))
        XCTAssertFalse(ControllerPolicy.validPort(70_000))
    }

    func testMemoryFitIsConservative() {
        XCTAssertTrue(ControllerPolicy.fits(sizeBytes: 10 * 1_073_741_824, physicalMemory: 36 * 1_073_741_824))
        XCTAssertFalse(ControllerPolicy.fits(sizeBytes: 23 * 1_073_741_824, physicalMemory: 36 * 1_073_741_824))
        XCTAssertFalse(ControllerPolicy.fits(sizeBytes: nil, physicalMemory: 36 * 1_073_741_824))
    }

}

final class RecommendationModelTests: XCTestCase {
    func testIncompleteMetadataIsNotCompatible() {
        let item = ModelRecommendation(id: "test", name: "Unknown", source: "Fixture", runtime: "llama.cpp", role: .chat, quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown", compatibility: .unverified, rationale: "Missing metadata", updatedAt: nil)
        XCTAssertEqual(item.compatibility, .unverified)
        XCTAssertEqual(item.sizeText, "Unknown")
    }

    func testOversizedModelDoesNotFit() {
        XCTAssertFalse(ControllerPolicy.fits(sizeBytes: 510 * 1_000_000_000, physicalMemory: 36 * 1_073_741_824))
    }

    func testCompatibilityRejectsUnsafeMetadata() {
        let memory: UInt64 = 36 * 1_073_741_824
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: false, multimodal: false, cloudOnly: false, physicalMemory: memory), .compatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: true, multimodal: false, cloudOnly: false, physicalMemory: memory), .incompatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: false, multimodal: true, cloudOnly: false, physicalMemory: memory), .incompatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: false, multimodal: false, cloudOnly: true, physicalMemory: memory), .incompatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: nil, architectureKnown: true, gated: false, multimodal: false, cloudOnly: false, physicalMemory: memory), .unverified)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: false, gated: false, multimodal: false, cloudOnly: false, physicalMemory: memory), .unverified)
    }
}

@MainActor
private final class FakeProbe: SystemProbing {
    let supportDirectory: URL
    var physicalMemory: UInt64 = 36 * 1_073_741_824
    var commands: [String: String] = ["tailscale": "/fake/tailscale", "llama-server": "/fake/llama-server", "ollama": "/fake/ollama"]
    var occupiedPorts: Set<Int> = []
    var portListeningCheck: ((Int) -> Bool)?
    var tailnetIP: String? = "100.64.0.1"
    var lanIP: String? = "192.168.1.10"
    var diskBytes: Int64 = 100_000_000_000
    var script: URL?
    var processRunning = false
    var processRunningCheck: ((Int32) -> Bool)?
    var processCommandValue = "bash start_llama_network.sh"
    var healthy = false
    var lastHealthPort: Int?
    var lastHealthHost: String?
    init(directory: URL) { supportDirectory = directory }
    func commandPath(_ command: String) -> String? { commands[command] }
    func isPortListening(_ port: Int) -> Bool { portListeningCheck?(port) ?? occupiedPorts.contains(port) }
    func tailscaleIP() -> String? { tailnetIP }
    func localNetworkIP() -> String? { lanIP }
    func availableDiskBytes() -> Int64 { diskBytes }
    func scriptURL(named name: String) -> URL? { script }
    func isProcessRunning(_ pid: Int32) -> Bool { processRunningCheck?(pid) ?? processRunning }
    func processCommand(_ pid: Int32) -> String { processCommandValue }
    func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool { lastHealthPort = port; lastHealthHost = host; return healthy }
}

@MainActor
private final class FakeProcessFactory: ProcessMaking {
    var onMake: (() -> Void)?
    var lastProcess: Process?
    func makeProcess() -> Process { onMake?(); let process = Process(); lastProcess = process; return process }
}

@MainActor
final class StartupDiagnosticsTests: XCTestCase {
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

    func testSuccessfulRetryClearsFailureAndRetainsHistory() async throws {
        let (directory, probe, defaults) = context(); probe.commands["llama-server"] = nil
        let factory = FakeProcessFactory()
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
        await manager.start(.llamaChat)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .failed)

        let script = directory.appendingPathComponent("running.sh")
        try "#!/bin/bash\nsleep 5\n".write(to: script, atomically: true, encoding: .utf8)
        probe.commands["llama-server"] = "/fake/llama-server"; probe.script = script
        factory.onMake = { probe.occupiedPorts.insert(11437); probe.processRunning = true; probe.healthy = true }
        await manager.start(.llamaChat)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .running)
        XCTAssertNil(manager.presentedFailure)
        let log = manager.services.first { $0.id == .llamaChat }?.logText ?? ""
        XCTAssertTrue(log.contains("llama-server is not installed"))
        XCTAssertEqual(log.components(separatedBy: "START ATTEMPT").count - 1, 2)
        factory.lastProcess?.terminate()
    }

    func testIntentionalSignalTerminationEndsStoppedWithoutFailure() async throws {
        let (directory, probe, defaults) = context()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script
        probe.healthy = true
        probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory()
        probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
        await manager.start(.llamaChat)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .running)
        await manager.stop(.llamaChat)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .stopped)
        XCTAssertNil(manager.presentedFailure)
    }

    func testManagedServiceContinuesUsingRecordedPortAfterPreferenceChanges() async throws {
        let (directory, probe, defaults) = context()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.healthy = true
        probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory()
        probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
        await manager.start(.llamaChat)
        var edited = manager.configuration(for: .llamaChat); edited.port = 12000
        manager.updateConfiguration(edited, for: .llamaChat)
        XCTAssertEqual(manager.configuration(for: .llamaChat).port, 11437)
        probe.lastHealthPort = nil
        await manager.refreshStatuses()
        XCTAssertEqual(probe.lastHealthPort, 11437)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.endpoint, "http://100.64.0.1:11437/v1")
        await manager.stop(.llamaChat)
    }

    func testStopTimeoutRetainsOwnershipAndCanFinishLater() async throws {
        let (directory, probe, defaults) = context()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap '' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.healthy = true; probe.processRunning = true
        let factory = FakeProcessFactory()
        probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false, stopPollAttempts: 1)
        await manager.start(.llamaChat)
        await manager.stop(.llamaChat)
        let service = manager.services.first { $0.id == .llamaChat }
        XCTAssertEqual(service?.state, .running)
        XCTAssertEqual(service?.pid, factory.lastProcess?.processIdentifier)
        XCTAssertTrue(service?.statusText.contains("timed out") == true)
        XCTAssertTrue(manager.hasManagedRunningServices)
        if let pid = factory.lastProcess?.processIdentifier { kill(pid, SIGKILL) }
        probe.processRunning = false
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .stopped)
        XCTAssertNil(manager.presentedFailure)
    }

    func testStartingProcessCountsAsManagedAndLiveLogCanBeClearedSafely() async throws {
        let (directory, probe, defaults) = context()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do echo tick; sleep 0.05; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.healthy = false
        probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory()
        probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
        await manager.start(.llamaChat)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.state, .starting)
        XCTAssertTrue(manager.hasManagedRunningServices)

        manager.clearLog(.llamaChat)
        try await Task.sleep(for: .milliseconds(200))
        let data = try Data(contentsOf: manager.logURL(.llamaChat))
        XCTAssertFalse(data.contains(0))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("tick"))
        await manager.stop(.llamaChat)
    }

    func testExternalServiceHasEndpoint() async {
        let (_, probe, defaults) = context(); probe.occupiedPorts.insert(11435)
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.refreshStatuses()
        let service = manager.services.first { $0.id == .autocomplete }
        XCTAssertEqual(service?.state, .external)
        XCTAssertEqual(service?.endpoint, "http://100.64.0.1:11435/v1")
    }

    func testProfilesMigratePersistAndReset() {
        let (directory, probe, defaults) = context(); defaults.set(12345, forKey: "llamaChatPort")
        let first = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        XCTAssertEqual(first.configuration(for: .llamaChat).port, 12345)
        XCTAssertEqual(first.configuration(for: .ollama), .defaultValue(for: .ollama))
        var edited = first.configuration(for: .autocomplete); edited.port = 13000; edited.bindMode = .localhost
        first.updateConfiguration(edited, for: .autocomplete)
        let secondProbe = FakeProbe(directory: directory)
        let second = ServiceManager(probe: secondProbe, defaults: defaults, startTimer: false)
        XCTAssertEqual(second.configuration(for: .autocomplete), edited)
        second.resetConfiguration(.autocomplete)
        XCTAssertEqual(second.configuration(for: .autocomplete), .defaultValue(for: .autocomplete))
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

private struct StubRecommendationProvider: RecommendationProvider {
    let sourceName: String
    let result: Result<[ModelRecommendation], Error>
    func fetch() async throws -> [ModelRecommendation] { try result.get() }
}

@MainActor
final class RecommendationStoreResilienceTests: XCTestCase {
    func testCompleteProviderFailureRetainsCacheAndDoesNotAdvanceLastChecked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appendingPathComponent("recommendations.json")
        let cached = ModelRecommendation(
            id: "cached", name: "Cached", source: "Registry", runtime: "llama.cpp", role: .chat,
            quantization: "Q4_K_M", sizeBytes: 1_000, context: "test", license: "test",
            compatibility: .compatible, rationale: "test", updatedAt: nil
        )
        try JSONEncoder().encode([cached]).write(to: cache)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let provider = StubRecommendationProvider(sourceName: "Registry", result: .failure(URLError(.notConnectedToInternet)))
        let store = RecommendationStore(providers: [provider], defaults: defaults, cacheURL: cache, startTimer: false)
        await store.refresh()
        XCTAssertEqual(store.recommendations.map(\.id), ["cached"])
        XCTAssertNil(store.lastChecked)
        let persisted = try JSONDecoder().decode([ModelRecommendation].self, from: Data(contentsOf: cache))
        XCTAssertEqual(persisted.map(\.id), ["cached"])
    }
}
