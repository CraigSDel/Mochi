// Tests/MochiTests/Domain/ContextMemoryPolicyTests.swift
import XCTest

@testable import Mochi

final class ContextMemoryPolicyTests: XCTestCase {
  private let gib = Int64(1_073_741_824)

  func testContextOptionsNormalizeAndFormat() {
    XCTAssertEqual(ContextSizeOptions.normalized(1), 4_096)
    XCTAssertEqual(ContextSizeOptions.normalized(12_000), 8_192)
    XCTAssertEqual(ContextSizeOptions.normalized(200_000), 262_144)
    XCTAssertEqual(ContextSizeOptions.normalized(999_999), 262_144)
    XCTAssertEqual(ContextSizeOptions.label(for: 32_768), "32K")
  }

  func testMemoryAssessmentClassifiesThresholds() {
    let memory = UInt64(24) * 1_073_741_824
    let safe = ControllerPolicy.memoryAssessment(
      modelBytes: [6 * gib], contextSize: 4_096, physicalMemory: memory)
    let caution = ControllerPolicy.memoryAssessment(
      modelBytes: [125 * gib / 16], contextSize: 4_096, physicalMemory: memory)
    let high = ControllerPolicy.memoryAssessment(
      modelBytes: [10 * gib], contextSize: 4_096, physicalMemory: memory)
    XCTAssertEqual(safe.severity, .safe)
    XCTAssertEqual(caution.severity, .caution)
    XCTAssertEqual(high.severity, .high)
    XCTAssertTrue(caution.requiresConfirmation)
    XCTAssertTrue(high.message.contains("swap heavily"))
  }

  func testMemoryAssessmentScalesWithContextConcurrencyAndLoadedModels() {
    let base = ControllerPolicy.memoryAssessment(
      modelBytes: [gib], contextSize: 4_096, physicalMemory: UInt64.max)
    let scaled = ControllerPolicy.memoryAssessment(
      modelBytes: [gib], contextSize: 8_192, parallelRequests: 2, loadedModelCount: 2,
      physicalMemory: UInt64.max)
    XCTAssertNotNil(base.estimatedBytes)
    XCTAssertGreaterThan(scaled.estimatedBytes!, base.estimatedBytes!)
    XCTAssertEqual(scaled.estimatedBytes! - UInt64(gib), 8 * (base.estimatedBytes! - UInt64(gib)))
  }

  func testMissingModelMetadataIsUnverified() {
    let assessment = ControllerPolicy.memoryAssessment(modelBytes: nil, contextSize: 32_768)
    XCTAssertEqual(assessment.severity, .unverified)
    XCTAssertNil(assessment.estimatedBytes)
    XCTAssertTrue(assessment.requiresConfirmation)
  }
}
