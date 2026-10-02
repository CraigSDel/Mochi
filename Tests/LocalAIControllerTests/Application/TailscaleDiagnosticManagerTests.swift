// Tests/LocalAIControllerTests/Application/TailscaleDiagnosticManagerTests.swift
import XCTest
@testable import LocalAIController

@MainActor
final class TailscaleDiagnosticManagerTests: XCTestCase {
    private func context() -> (ServiceManager, FakeProbe) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return (ServiceManager(probe: probe, defaults: defaults, startTimer: false), probe)
    }

    func testManualTestPublishesResult() async {
        let (manager, probe) = context()
        probe.diagnostic = .init(status: .relayed, peer: "laptop", detail: "via DERP", checkedAt: Date())
        let result = await manager.testTailscale()
        XCTAssertEqual(result.status, .relayed)
        XCTAssertEqual(manager.latestTailscaleDiagnostic, result)
        XCTAssertFalse(manager.isTestingTailscale)
        XCTAssertEqual(probe.diagnosticCallCount, 1)
    }

    func testLaunchDiagnosticOnlyRunsForTailscaleBinding() async {
        let (manager, probe) = context()
        var config = manager.configuration(for: .llamaChat)
        config.bindMode = .localhost
        manager.updateConfiguration(config, for: .llamaChat)
        let localWarning = await manager.tailscaleLaunchWarning(for: [.llamaChat])
        XCTAssertNil(localWarning)
        XCTAssertEqual(probe.diagnosticCallCount, 0)
        config.bindMode = .tailscale
        manager.updateConfiguration(config, for: .llamaChat)
        let directWarning = await manager.tailscaleLaunchWarning(for: [.llamaChat])
        XCTAssertNil(directWarning)
        XCTAssertEqual(probe.diagnosticCallCount, 1)
    }

    func testRelayAndFailureAreAdvisoryWarnings() async {
        let (manager, probe) = context()
        probe.diagnostic = .init(status: .relayed, peer: "laptop", detail: "via DERP", checkedAt: Date())
        let relayWarning = await manager.tailscaleLaunchWarning(for: ServiceManager.startAllServiceIDs)
        XCTAssertTrue(relayWarning?.message.contains("relay") == true)
        probe.diagnostic = .init(status: .unreachable, peer: "laptop", detail: "timeout", checkedAt: Date())
        let failureWarning = await manager.tailscaleLaunchWarning(for: ServiceManager.startAllServiceIDs)
        XCTAssertTrue(failureWarning?.message.contains("blocked") == true)
        XCTAssertEqual(probe.diagnosticCallCount, 2)
    }
}
