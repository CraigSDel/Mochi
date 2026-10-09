import XCTest

@testable import Mochi

@MainActor
final class StartupConfigurationNetworkTests: XCTestCase {
  func testLanLaunchUsesLoopbackHealthAndLanDisplayEndpoint() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let probe = FakeProbe(directory: directory)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    probe.healthy = true
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("start_llama_network.sh")
    try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(
      to: script, atomically: true, encoding: .utf8)
    probe.script = script
    probe.processRunningCheck = { kill($0, 0) == 0 }
    let factory = FakeProcessFactory()
    probe.portListeningCheck = { _ in factory.lastProcess?.isRunning == true }
    let manager = ServiceManager(
      probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
    var config = manager.configuration(for: .llamaChat)
    config.bindMode = .lan
    manager.updateConfiguration(config, for: .llamaChat)
    await manager.start(.llamaChat, warningsAcknowledged: true)
    XCTAssertEqual(probe.lastHealthHost, "127.0.0.1")
    XCTAssertEqual(
      manager.services.first { $0.id == .llamaChat }?.endpoint, "http://192.168.1.10:11437/v1")
    await manager.stop(.llamaChat)
  }
}
