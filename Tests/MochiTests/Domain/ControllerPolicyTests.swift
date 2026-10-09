// Tests/MochiTests/Domain/ControllerPolicyTests.swift
import XCTest
@testable import Mochi

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
