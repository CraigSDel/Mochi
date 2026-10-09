import XCTest
@testable import Mochi

@MainActor
final class ProcessIdentityTests: XCTestCase {
    func testRefreshKeepsExecReplacedRuntimeRunning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let runtime = "llama-server -hf owner/model -hff model.gguf --host 127.0.0.1 --port 11437"
        let record = ManagedProcessRecord(
            serviceID: .llamaChat, pid: 321, port: 11437,
            expectedCommand: "/bin/bash /Applications/LocalAI/start_llama_network.sh --model chat --bind localhost",
            runtimeCommand: runtime, startedAt: Date(),
            logPath: directory.appendingPathComponent("llamaChat.log").path, bindMode: .localhost
        )
        try JSONEncoder().encode([record]).write(to: directory.appendingPathComponent("processes.json"))
        probe.processRunningCheck = { $0 == record.pid }
        probe.processCommandValue = runtime
        probe.occupiedPorts.insert(record.port)
        probe.healthy = true

        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        await manager.refreshStatuses()

        let service = manager.services.first { $0.id == .llamaChat }
        XCTAssertEqual(service?.state, .running)
        XCTAssertEqual(service?.pid, record.pid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("processes.json").path))
    }
}
