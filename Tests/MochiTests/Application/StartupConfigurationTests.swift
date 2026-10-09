import XCTest
@testable import Mochi

@MainActor
final class StartupConfigurationTests: XCTestCase {
    private func context() -> (URL, FakeProbe, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return (directory, probe, defaults)
    }

    func testDownloadModesProduceAuditableArguments() {
        let script = URL(fileURLWithPath: "/tmp/start.sh")
        let cached = ServiceLaunchConfiguration.defaultValue(for: .llamaChat)
        var downloads = cached; downloads.downloadPolicy = .allowDownloads
        XCTAssertTrue(LaunchInvocation.arguments(id: .llamaChat, script: script, modelChoice: "chat", configuration: cached).contains("--offline"))
        XCTAssertFalse(LaunchInvocation.arguments(id: .llamaChat, script: script, modelChoice: "chat", configuration: downloads).contains("--offline"))
    }

    func testLaunchEnvironmentIncludesSystemAdministrationPaths() {
        let environment = LaunchInvocation.environment(id: .llamaChat, configuration: .defaultValue(for: .llamaChat), base: ["PATH": "/usr/bin:/bin", "PRESERVED": "yes"])
        let paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        XCTAssertTrue(paths.contains("/usr/sbin"))
        XCTAssertTrue(paths.contains("/sbin"))
        XCTAssertEqual(environment["PRESERVED"], "yes")
        XCTAssertEqual(environment["LLAMA_CHAT_REPO"], "unsloth/Qwen3.8-27B-GGUF")
        XCTAssertEqual(environment["LLAMA_CHAT_PORT"], "11437")
    }

    func testLaunchEnvironmentContainsEveryConfiguredRuntimeValue() {
        var llama = ServiceLaunchConfiguration.defaultValue(for: .autocomplete)
        llama.port = 12002; llama.llama = .init(repository: "owner/repo", filename: "model.gguf", alias: "custom", contextSize: 4096, gpuLayers: 42)
        let llamaEnvironment = LaunchInvocation.environment(id: .autocomplete, configuration: llama, base: [:])
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_PORT"], "12002")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_REPO"], "owner/repo")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_FILE"], "model.gguf")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_ALIAS"], "custom")
        XCTAssertEqual(llamaEnvironment["LLAMA_AUTOCOMPLETE_CONTEXT"], "4096")
        XCTAssertEqual(llamaEnvironment["LLAMA_GPU_LAYERS"], "42")

    }

    func testEffectiveBindModeOnlyOverridesTailscaleWithLocalhost() {
        XCTAssertEqual(ServiceManager.effectiveBindMode(configured: .tailscale, override: .localhost), .localhost)
        XCTAssertEqual(ServiceManager.effectiveBindMode(configured: .tailscale, override: .lan), .lan)
        XCTAssertEqual(ServiceManager.effectiveBindMode(configured: .localhost, override: .localhost), .localhost)
        XCTAssertEqual(ServiceManager.effectiveBindMode(configured: .localhost, override: .lan), .localhost)
        XCTAssertEqual(ServiceManager.effectiveBindMode(configured: .lan, override: .localhost), .lan)
        XCTAssertEqual(ServiceManager.effectiveBindMode(configured: .tailscale, override: nil), .tailscale)
    }

    func testEndpointIncludesHostPortAndRuntimePath() {
        XCTAssertEqual(ServiceManager.endpoint(.llamaChat, 11437, "100.64.0.1"), "http://100.64.0.1:11437/v1")
        XCTAssertEqual(ServiceManager.endpoint(.autocomplete, 11435, "127.0.0.1"), "http://127.0.0.1:11435/v1")
    }

    func testLegacyManagedProcessRecordDecodesWithDefaultableBindMode() throws {
        let json = #"[{"serviceID":"llamaChat","pid":123,"port":11437,"expectedCommand":"start_llama_network.sh","startedAt":0,"logPath":"/tmp/test.log"}]"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let records = try decoder.decode([ManagedProcessRecord].self, from: Data(json.utf8))
        XCTAssertNil(records.first?.bindMode)
    }

    func testMemoryRootsRequireRunningPIDAndMatchingLaunchCommand() async throws {
        let (directory, probe, defaults) = context()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = ManagedProcessRecord(
            serviceID: .llamaChat,
            pid: 123,
            port: 11437,
            expectedCommand: "start_llama_network.sh",
            startedAt: Date(),
            logPath: directory.appendingPathComponent("llamaChat.log").path,
            bindMode: .localhost
        )
        try JSONEncoder().encode([record]).write(to: directory.appendingPathComponent("processes.json"))
        probe.processRunningCheck = { $0 == 123 }
        probe.occupiedPorts.insert(11437)
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.refreshStatuses()

        XCTAssertEqual(manager.managedProcessMemoryRoots[.llamaChat], .owned(pid: 123))
        XCTAssertEqual(manager.managedProcessMemoryRoots[.autocomplete], .noOwnedPID(reason: "No launch record"))

        probe.processRunningCheck = { _ in false }
        await manager.refreshStatuses()
        XCTAssertEqual(manager.managedProcessMemoryRoots[.llamaChat], .noOwnedPID(reason: "Recorded PID 123 is not running"))

        probe.processRunningCheck = { _ in true }
        probe.processCommandValue = "unrelated-process"
        try JSONEncoder().encode([record]).write(to: directory.appendingPathComponent("processes.json"))
        await manager.refreshStatuses()
        XCTAssertEqual(manager.managedProcessMemoryRoots[.llamaChat], .noOwnedPID(reason: "Recorded PID 123 command does not match the expected runtime"))
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

    func testStartAllIncludesOnlyLlamaServices() {
        XCTAssertEqual(ServiceManager.startAllServiceIDs, [.llamaChat, .autocomplete, .embeddings])
    }

    func testStartAllPortCollisionsAreDetected() {
        let (_, probe, defaults) = context(); let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        var embeddings = manager.configuration(for: .embeddings)
        embeddings.port = manager.configuration(for: .autocomplete).port
        manager.updateConfiguration(embeddings, for: .embeddings)
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

    func testOneTimeLocalFallbackPreservesConfigurationAndRecordAndLogsEndpointOnce() async throws {
        let (directory, probe, defaults) = context(); probe.commands["tailscale"] = nil; probe.tailnetIP = nil; probe.healthy = true
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory(); probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: defaults, startTimer: false)

        await manager.start(.llamaChat, warningsAcknowledged: true, bindModeOverride: .localhost)

        XCTAssertEqual(manager.configuration(for: .llamaChat).bindMode, .tailscale)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.endpoint, "http://127.0.0.1:11437/v1")
        XCTAssertEqual(probe.lastHealthHost, "127.0.0.1")
        let data = try Data(contentsOf: directory.appendingPathComponent("processes.json"))
        XCTAssertEqual(try JSONDecoder().decode([ManagedProcessRecord].self, from: data).first?.bindMode, .localhost)
        await manager.refreshStatuses(); await manager.refreshStatuses()
        let log = manager.services.first { $0.id == .llamaChat }?.logText ?? ""
        XCTAssertEqual(log.components(separatedBy: "Model available at http://127.0.0.1:11437/v1").count - 1, 1)
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
    }}

