import XCTest
@testable import LocalAIController

final class ControllerPolicyTests: XCTestCase {
    func testPortValidation() {
        XCTAssertTrue(ControllerPolicy.validPort(11437))
        XCTAssertFalse(ControllerPolicy.validPort(80))
        XCTAssertFalse(ControllerPolicy.validPort(70_000))
    }

    func testMemoryFitIsConservative() {
        XCTAssertTrue(ControllerPolicy.fits(sizeBytes: 10 * 1_073_741_824, physicalMemory: 36 * 1_073_741_824))
        XCTAssertFalse(ControllerPolicy.fits(sizeBytes: 23 * 1_073_741_824, physicalMemory: 36 * 1_073_741_824))
        XCTAssertFalse(ControllerPolicy.fits(sizeBytes: nil, physicalMemory: 36 * 1_073_741_824))
    }
}

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

final class SidebarDestinationTests: XCTestCase {
    func testTopLevelDestinationsAreDistinctFromEveryServiceDestination() {
        let recommendations = SidebarDestination.recommendations
        let overview = SidebarDestination.overview

        for serviceID in ServiceID.allCases {
            XCTAssertNotEqual(recommendations, .service(serviceID))
            XCTAssertNotEqual(overview, .service(serviceID))
        }
        XCTAssertNotEqual(overview, recommendations)
    }

    func testEveryServiceHasAUniqueDestination() {
        let destinations = ServiceID.allCases.map(SidebarDestination.service)

        XCTAssertEqual(Set(destinations).count, ServiceID.allCases.count)
    }

    func testOverviewIsTheInitialDestination() {
        XCTAssertEqual(SidebarDestination.initial, .overview)
    }
}

final class ServiceStatePresentationTests: XCTestCase {
    func testEveryStateHasPresentationMetadata() {
        for state in [ServiceState.unavailable, .stopped, .starting, .running, .stopping, .failed, .external] {
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.symbolName.isEmpty)
        }
    }

    func testStateActionAvailability() {
        XCTAssertTrue(ServiceState.stopped.canStart)
        XCTAssertTrue(ServiceState.failed.canStart)
        XCTAssertTrue(ServiceState.unavailable.canStart)
        XCTAssertFalse(ServiceState.external.canStart)
        XCTAssertTrue(ServiceState.running.canStop)
        XCTAssertTrue(ServiceState.starting.canStop)
        XCTAssertFalse(ServiceState.stopping.canStop)
    }

    func testSemanticStateTones() {
        XCTAssertEqual(ServiceState.running.tone, .success)
        XCTAssertEqual(ServiceState.failed.tone, .danger)
        XCTAssertEqual(ServiceState.starting.tone, .warning)
        XCTAssertEqual(ServiceState.external.tone, .accent)
        XCTAssertEqual(ServiceState.stopped.tone, .neutral)
    }
}
