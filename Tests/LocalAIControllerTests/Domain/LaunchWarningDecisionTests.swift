// Tests/LocalAIControllerTests/Domain/LaunchWarningDecisionTests.swift
import XCTest
@testable import LocalAIController

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
}
