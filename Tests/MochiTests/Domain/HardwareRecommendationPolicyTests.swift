import XCTest
@testable import Mochi

final class HardwareRecommendationPolicyTests: XCTestCase {
    private let policy = HardwareRecommendationPolicy()
    private let memory: UInt64 = 36 * 1_073_741_824

    func test_36GBProfile_recommendsEachRoleAndExplainsHardwareBasis() {
        let result = policy.evaluate(profile: profile(), catalogRecommendations: catalog(), installedModels: [])

        XCTAssertTrue(RecommendationRole.allCases.allSatisfy { !result.recommendations(for: $0).isEmpty })
        XCTAssertTrue(result.message.contains("36"))
        XCTAssertTrue(result.recommendations.allSatisfy { $0.fit == .safe })
    }

    func test_oversizedAndUnknownModels_areExcluded() {
        let oversized = recommendation(id: "huge", role: .chat, size: 30_000_000_000)
        let unknown = recommendation(id: "unknown", role: .chat, size: nil)

        let result = policy.evaluate(profile: profile(), catalogRecommendations: [oversized, unknown], installedModels: [])

        XCTAssertTrue(result.recommendations.isEmpty)
    }

    func test_safeModels_rankBeforeCautionAndResultsAreDeterministic() {
        let safe = recommendation(id: "safe", role: .chat, size: 8_000_000_000)
        let caution = recommendation(id: "caution", role: .chat, size: 20_000_000_000)

        let result = policy.evaluate(profile: profile(), catalogRecommendations: [caution, safe], installedModels: [])

        XCTAssertEqual(result.recommendations(for: .chat).map(\.modelID), [
            "llama:owner/safe:safe.gguf", "llama:owner/caution:caution.gguf"
        ])
    }

    func test_missingHardware_returnsUnverifiedExplanation() {
        let result = policy.evaluate(profile: nil, catalogRecommendations: catalog(), installedModels: [])

        XCTAssertTrue(result.recommendations.isEmpty)
        XCTAssertTrue(result.message.contains("unavailable"))
    }

    func test_inputChanges_recalculateWithoutPersistence() {
        let first = policy.evaluate(profile: profile(memory: 16 * 1_073_741_824), catalogRecommendations: catalog(), installedModels: [])
        let second = policy.evaluate(profile: profile(memory: memory), catalogRecommendations: catalog(), installedModels: [])

        XCTAssertNotEqual(first.recommendations.map(\.id), second.recommendations.map(\.id))
    }

    private func profile(memory: UInt64? = nil) -> HardwareProfile {
        .init(architecture: .appleSilicon, modelIdentifier: "Mac", chipName: "Apple M3 Pro", chipFamily: "M3", chipGeneration: 3,
              physicalMemory: memory ?? self.memory, cpuCoreCount: 12, performanceCoreCount: 6, efficiencyCoreCount: 6,
              gpuCoreCount: 18, detectedAt: Date(), unavailableFields: [])
    }

    private func catalog() -> [ModelRecommendation] {
        [
            recommendation(id: "chat", role: .chat, size: 8_000_000_000),
            recommendation(id: "code", role: .coding, size: 2_000_000_000),
            recommendation(id: "embed", role: .embedding, size: 1_000_000_000)
        ]
    }

    private func recommendation(id: String, role: RecommendationRole, size: Int64?) -> ModelRecommendation {
        .init(id: id, name: id, source: "Fixture", runtime: "llama.cpp", role: role, quantization: "Q4", sizeBytes: size,
              context: "verified", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil,
              repository: "owner/\(id)", filename: "\(id).gguf")
    }
}
