import XCTest
@testable import LocalAIController

final class TailscaleDiagnosticsTests: XCTestCase {
    func testStatusSelectsOnlinePeerDeterministically() throws {
        let json = #"{"BackendState":"Running","Peer":{"b":{"HostName":"zeta","TailscaleIPs":["100.1.1.2"],"Online":true},"a":{"HostName":"alpha","TailscaleIPs":["100.1.1.1"],"Online":true},"off":{"HostName":"offline","TailscaleIPs":["100.1.1.3"],"Online":false}}}"#
        let result = try TailscaleStatusParser.connectedAndPeer(from: Data(json.utf8))
        XCTAssertTrue(result.connected)
        XCTAssertEqual(result.peer, .init(name: "alpha", target: "100.1.1.1"))
    }

    func testStatusReportsDisconnectedAndNoPeers() throws {
        let disconnected = try TailscaleStatusParser.connectedAndPeer(from: Data(#"{"BackendState":"Stopped"}"#.utf8))
        XCTAssertFalse(disconnected.connected)
        let empty = try TailscaleStatusParser.connectedAndPeer(from: Data(#"{"BackendState":"Running","Peer":{}}"#.utf8))
        XCTAssertTrue(empty.connected)
        XCTAssertNil(empty.peer)
    }

    func testMalformedStatusThrows() {
        XCTAssertThrowsError(try TailscaleStatusParser.connectedAndPeer(from: Data("not-json".utf8)))
    }

    func testPingClassifiesDirectRelayPeerRelayAndFailure() {
        XCTAssertEqual(TailscaleStatusParser.pingStatus(output: "pong from peer via 192.0.2.1:41641", exitCode: 0), .direct)
        XCTAssertEqual(TailscaleStatusParser.pingStatus(output: "pong from peer via DERP(fra)", exitCode: 0), .relayed)
        XCTAssertEqual(TailscaleStatusParser.pingStatus(output: "pong via peer-relay 100.2.3.4", exitCode: 0), .relayed)
        XCTAssertEqual(TailscaleStatusParser.pingStatus(output: "timeout", exitCode: 1), .unreachable)
    }

    func testEveryDiagnosticFailureHasActionablePresentation() {
        for status in [TailscaleDiagnosticStatus.noOnlinePeers, .disconnected, .missingCLI, .commandFailure, .unreachable] {
            let result = TailscaleDiagnostic(status: status, peer: nil, detail: "test", checkedAt: Date())
            XCTAssertFalse(result.title.isEmpty)
            XCTAssertFalse(result.guidance.isEmpty)
            XCTAssertNotNil(result.launchWarning)
        }
    }
}

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
        var config = manager.configuration(for: .llamaChat); config.bindMode = .localhost
        manager.updateConfiguration(config, for: .llamaChat)
        let localWarning = await manager.tailscaleLaunchWarning(for: [.llamaChat])
        XCTAssertNil(localWarning)
        XCTAssertEqual(probe.diagnosticCallCount, 0)

        config.bindMode = .tailscale; manager.updateConfiguration(config, for: .llamaChat)
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
