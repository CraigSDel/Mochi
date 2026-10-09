import XCTest
@testable import LocalAIController

@MainActor
final class NetworkFallbackTests: XCTestCase {
    func testWiFiAvailabilityComesFromProbe() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        let initialIP = await manager.wifiIP()
        XCTAssertEqual(initialIP, "192.168.1.10")
        probe.wifiIPv4 = nil
        let missingIP = await manager.wifiIP()
        XCTAssertNil(missingIP)
    }

    func testWiFiFallbackRecordsLANAndDisplaysWiFiWithoutChangingSavedMode() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory); probe.healthy = true; probe.wifiIPv4 = "192.168.50.24"; probe.lanIP = "10.0.0.8"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("start_llama_network.sh")
        try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(to: script, atomically: true, encoding: .utf8)
        probe.script = script; probe.processRunningCheck = { kill($0, 0) == 0 }
        let factory = FakeProcessFactory(); probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
        let manager = ServiceManager(probe: probe, processFactory: factory, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)

        await manager.start(.llamaChat, warningsAcknowledged: true, bindModeOverride: .lan)

        XCTAssertEqual(manager.configuration(for: .llamaChat).bindMode, .tailscale)
        XCTAssertEqual(manager.services.first { $0.id == .llamaChat }?.endpoint, "http://192.168.50.24:11437/v1")
        XCTAssertTrue(factory.lastProcess?.arguments?.contains("lan") == true)
        let records = try JSONDecoder().decode([ManagedProcessRecord].self, from: Data(contentsOf: directory.appendingPathComponent("processes.json")))
        XCTAssertEqual(records.first?.bindMode, .lan)
        await manager.stop(.llamaChat)
    }
}
