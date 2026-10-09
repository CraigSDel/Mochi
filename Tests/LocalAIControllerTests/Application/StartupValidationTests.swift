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
            let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
            XCTAssertTrue(manager.launchWarnings(for: [.llamaChat]).contains { $0.message.contains("safe budget") })
            await manager.start(.llamaChat)
            XCTAssertEqual(manager.presentedFailure?.message, "Launch confirmation is required.")
            await manager.start(.llamaChat, warningsAcknowledged: true)
            XCTAssertEqual(manager.presentedFailure?.message, "Could not locate start_llama_network.sh.")
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

}
