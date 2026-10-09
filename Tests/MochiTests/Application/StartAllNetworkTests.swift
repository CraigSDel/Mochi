import XCTest

@testable import Mochi

@MainActor
final class StartAllNetworkTests: XCTestCase {
  private func context() -> (URL, FakeProbe, UserDefaults) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let probe = FakeProbe(directory: directory)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    return (directory, probe, defaults)
  }

  func testStartAllLocalhostOverridesMixedModesWithoutPersisting() async throws {
    let (directory, probe, defaults) = context()
    probe.commands["tailscale"] = nil
    probe.tailnetIP = nil
    probe.healthy = true
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("start_llama_network.sh")
    try "#!/bin/bash\ntrap 'exit 0' TERM\nwhile true; do sleep 0.1; done\n".write(
      to: script, atomically: true, encoding: .utf8)
    probe.script = script
    probe.processRunningCheck = { kill($0, 0) == 0 }
    let factory = FakeProcessFactory()
    probe.portListeningCheck = { port in
      guard let data = try? Data(contentsOf: directory.appendingPathComponent("processes.json"))
      else { return false }
      let records = try? JSONDecoder().decode([ManagedProcessRecord].self, from: data)
      return records?.contains { $0.port == port && factory.lastProcess?.isRunning == true } == true
    }
    let manager = ServiceManager(
      probe: probe, processFactory: factory, defaults: defaults, startTimer: false)
    var autocomplete = manager.configuration(for: .autocomplete)
    autocomplete.bindMode = .localhost
    manager.updateConfiguration(autocomplete, for: .autocomplete)
    let savedModes = Dictionary(
      uniqueKeysWithValues: ServiceManager.startAllServiceIDs.map {
        ($0, manager.configuration(for: $0).bindMode)
      })

    await manager.startAll(warningsAcknowledged: true, bindModeOverride: .localhost)

    for id in ServiceManager.startAllServiceIDs {
      XCTAssertEqual(manager.services.first { $0.id == id }?.state, .running)
      XCTAssertEqual(manager.services.first { $0.id == id }?.endpoint?.contains("127.0.0.1"), true)
      XCTAssertEqual(manager.configuration(for: id).bindMode, savedModes[id])
      XCTAssertTrue(
        manager.services.first { $0.id == id }?.logText.contains("bind: Localhost") == true)
    }
    let data = try Data(contentsOf: directory.appendingPathComponent("processes.json"))
    let records = try JSONDecoder().decode([ManagedProcessRecord].self, from: data)
    XCTAssertEqual(records.count, ServiceManager.startAllServiceIDs.count)
    XCTAssertTrue(records.allSatisfy { $0.bindMode == .localhost })
    XCTAssertEqual(probe.lastHealthHost, "127.0.0.1")

    await manager.stopAll()
  }

  func testStartAllTailscaleOverrideValidatesSelectedMode() async {
    let (_, probe, defaults) = context()
    probe.commands["tailscale"] = nil
    probe.tailnetIP = nil
    let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
    for id in ServiceManager.startAllServiceIDs {
      var config = manager.configuration(for: id)
      config.bindMode = .localhost
      manager.updateConfiguration(config, for: id)
    }

    await manager.startAll(warningsAcknowledged: true, bindModeOverride: .tailscale)

    XCTAssertTrue(
      ServiceManager.startAllServiceIDs.allSatisfy { id in
        manager.services.first { $0.id == id }?.state == .failed
      })
    XCTAssertTrue(manager.presentedFailure?.message.contains("Tailscale") == true)
    XCTAssertTrue(
      ServiceManager.startAllServiceIDs.allSatisfy {
        manager.configuration(for: $0).bindMode == .localhost
      })
  }

  func testTailscaleDiagnosticUsesBulkOverrideForLocalConfigurations() async {
    let (_, probe, defaults) = context()
    probe.diagnostic = .init(
      status: .relayed, peer: "laptop", detail: "via DERP", checkedAt: Date())
    let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
    for id in ServiceManager.startAllServiceIDs {
      var config = manager.configuration(for: id)
      config.bindMode = .localhost
      manager.updateConfiguration(config, for: id)
    }

    let warning = await manager.tailscaleLaunchWarning(
      for: ServiceManager.startAllServiceIDs,
      bindModeOverride: .tailscale
    )

    XCTAssertTrue(warning?.message.contains("relay") == true)
    XCTAssertEqual(probe.diagnosticCallCount, 1)
  }
}
