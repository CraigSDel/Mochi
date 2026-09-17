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

final class RecommendationModelTests: XCTestCase {
    func testIncompleteMetadataIsNotCompatible() {
        let item = ModelRecommendation(id: "test", name: "Unknown", source: "Fixture", runtime: "llama.cpp", role: .chat, quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown", compatibility: .unverified, rationale: "Missing metadata", updatedAt: nil)
        XCTAssertEqual(item.compatibility, .unverified)
        XCTAssertEqual(item.sizeText, "Unknown")
    }

    func testOversizedModelDoesNotFit() {
        XCTAssertFalse(ControllerPolicy.fits(sizeBytes: 510 * 1_000_000_000, physicalMemory: 36 * 1_073_741_824))
    }

    func testCompatibilityRejectsUnsafeMetadata() {
        let memory: UInt64 = 36 * 1_073_741_824
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: false, multimodal: false, cloudOnly: false, physicalMemory: memory), .compatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: true, multimodal: false, cloudOnly: false, physicalMemory: memory), .incompatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: false, multimodal: true, cloudOnly: false, physicalMemory: memory), .incompatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: true, gated: false, multimodal: false, cloudOnly: true, physicalMemory: memory), .incompatible)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: nil, architectureKnown: true, gated: false, multimodal: false, cloudOnly: false, physicalMemory: memory), .unverified)
        XCTAssertEqual(ControllerPolicy.compatibility(sizeBytes: 8_000_000_000, architectureKnown: false, gated: false, multimodal: false, cloudOnly: false, physicalMemory: memory), .unverified)
    }
}
