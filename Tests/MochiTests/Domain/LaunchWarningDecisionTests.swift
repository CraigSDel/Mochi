// Tests/MochiTests/Domain/LaunchWarningDecisionTests.swift
import XCTest
@testable import Mochi

final class LaunchWarningDecisionTests: XCTestCase {
    func testDecisionControlsLaunchAndOneTimeOverride() {
        XCTAssertTrue(LaunchWarningDecision.configured.shouldStart)
        XCTAssertNil(LaunchWarningDecision.configured.bindModeOverride)
        XCTAssertTrue(LaunchWarningDecision.localhost.shouldStart)
        XCTAssertEqual(LaunchWarningDecision.localhost.bindModeOverride, .localhost)
        XCTAssertTrue(LaunchWarningDecision.lan.shouldStart)
        XCTAssertEqual(LaunchWarningDecision.lan.bindModeOverride, .lan)
        XCTAssertFalse(LaunchWarningDecision.cancel.shouldStart)
        XCTAssertNil(LaunchWarningDecision.cancel.bindModeOverride)
    }

    func testStartAllNetworkDecisionControlsLaunchAndMode() {
        XCTAssertTrue(StartAllNetworkDecision.tailscale.shouldStart)
        XCTAssertEqual(StartAllNetworkDecision.tailscale.bindMode, .tailscale)
        XCTAssertTrue(StartAllNetworkDecision.localhost.shouldStart)
        XCTAssertEqual(StartAllNetworkDecision.localhost.bindMode, .localhost)
        XCTAssertFalse(StartAllNetworkDecision.cancel.shouldStart)
        XCTAssertNil(StartAllNetworkDecision.cancel.bindMode)
    }
}
