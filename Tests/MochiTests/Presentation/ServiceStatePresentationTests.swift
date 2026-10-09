// Tests/MochiTests/Presentation/ServiceStatePresentationTests.swift
import XCTest
@testable import Mochi

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
