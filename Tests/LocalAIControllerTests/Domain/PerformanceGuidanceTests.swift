import XCTest
@testable import LocalAIController

final class PerformanceGuidanceTests: XCTestCase {
    private let memory = UInt64(36) * 1_073_741_824
    private let gib = Int64(1_073_741_824)

    func testLargeDenseModelOnThirtySixGigabytesWarnsAboutQuantizationAndMemory() {
        let guidance = PerformanceGuidance.make(
            runtime: .llamaCpp,
            modelLabel: "Qwen3.8-27B",
            modelBytes: [16 * gib],
            quantization: "Qwen3.8-27B-F16.gguf",
            contextSize: 16_384,
            physicalMemory: memory
        )

        XCTAssertEqual(guidance.severity, .safe)
        XCTAssertTrue(guidance.recommendations.contains { $0.contains("4-bit") })
        XCTAssertTrue(guidance.summary.contains("usable memory headroom"))
    }

    func testSmallFourBitModelIsNonAlarmist() {
        let guidance = PerformanceGuidance.make(
            runtime: .llamaCpp,
            modelLabel: "Small model",
            modelBytes: [4 * gib],
            quantization: "Q4_K_M",
            contextSize: 4_096,
            physicalMemory: memory
        )

        XCTAssertEqual(guidance.severity, .safe)
        XCTAssertFalse(guidance.recommendations.contains { $0.contains("prefer a 4-bit") })
        XCTAssertTrue(guidance.summary.contains("usable memory headroom"))
    }

    func testMLXRecommendationIsInformationalOnly() {
        let guidance = PerformanceGuidance.make(
            runtime: .llamaCpp,
            modelLabel: "Model",
            modelBytes: [4 * gib],
            quantization: "Q4_K_M",
            contextSize: 4_096,
            physicalMemory: memory
        )

        XCTAssertTrue(guidance.isInformational)
        XCTAssertTrue(guidance.recommendations.contains { $0.contains("does not install, launch, or manage") })
    }

}
