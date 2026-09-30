import XCTest
@testable import LocalAIController

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

    func testLegacyCacheDecodesWithoutLaunchMetadata() throws {
        let json = #"{"id":"old","name":"Old","source":"Fixture","runtime":"llama.cpp","role":"Chat / reasoning","quantization":"Q4_K_M","sizeBytes":1000,"context":"test","license":"test","compatibility":"Compatible","rationale":"test","updatedAt":null}"#.data(using: .utf8)!
        let model = try JSONDecoder().decode(ModelRecommendation.self, from: json)
        XCTAssertNil(model.repository)
        XCTAssertNil(model.filename)
        XCTAssertNil(model.modelName)
    }

    func testCompatibilityFilterCombinesWithRole() {
        let compatibleChat = recommendation(id: "compatible-chat", role: .chat, compatibility: .compatible)
        let compatibleCoding = recommendation(id: "compatible-coding", role: .coding, compatibility: .compatible)
        let unverifiedChat = recommendation(id: "unverified-chat", role: .chat, compatibility: .unverified)
        let recommendations = [compatibleChat, compatibleCoding, unverifiedChat]

        XCTAssertEqual(RecommendationCompatibilityFilter.all.apply(to: recommendations).map(\.id), recommendations.map(\.id))
        XCTAssertEqual(RecommendationCompatibilityFilter.compatibleOnly.apply(to: recommendations).map(\.id), ["compatible-chat", "compatible-coding"])
        XCTAssertEqual(RecommendationCompatibilityFilter.compatibleOnly.apply(to: recommendations, role: .chat).map(\.id), ["compatible-chat"])
    }

    func testCompatibilityFilterRoundTripsThroughDefaults() {
        let suiteName = "RecommendationCompatibilityFilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(RecommendationCompatibilityFilter.compatibleOnly.rawValue, forKey: "filter")
        XCTAssertEqual(RecommendationCompatibilityFilter(rawValue: defaults.string(forKey: "filter")!), .compatibleOnly)
    }

    func testCuratedLlamaCppRecommendationsAreLaunchableAndFitThisMac() async throws {
        let recommendations = try await CuratedLlamaCppProvider().fetch()

        XCTAssertEqual(Set(recommendations.map(\.role)), Set(RecommendationRole.allCases))
        XCTAssertTrue(recommendations.allSatisfy { $0.runtime == "llama.cpp" })
        XCTAssertTrue(recommendations.allSatisfy { $0.repository != nil && $0.filename?.hasSuffix(".gguf") == true })
        XCTAssertTrue(recommendations.allSatisfy { $0.compatibility == .compatible })
        for recommendation in recommendations {
            let options = ModelOptionBuilder.options(runtime: .llamaCpp, role: recommendation.role, installed: [], recommendations: [recommendation])
            XCTAssertEqual(options.first?.repository, recommendation.repository)
            XCTAssertEqual(options.first?.filename, recommendation.filename)
        }
    }

    private func recommendation(id: String, role: RecommendationRole, compatibility: Compatibility) -> ModelRecommendation {
        ModelRecommendation(id: id, name: id, source: "Fixture", runtime: "Ollama", role: role, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: compatibility, rationale: "test", updatedAt: nil, modelName: "\(id):latest")
    }
}
