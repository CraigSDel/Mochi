import XCTest
@testable import LocalAIController

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
        let safe = ControllerPolicy.memoryAssessment(modelBytes: [6 * gib], contextSize: 4_096, physicalMemory: memory)
        let caution = ControllerPolicy.memoryAssessment(modelBytes: [125 * gib / 16], contextSize: 4_096, physicalMemory: memory)
        let high = ControllerPolicy.memoryAssessment(modelBytes: [10 * gib], contextSize: 4_096, physicalMemory: memory)
        XCTAssertEqual(safe.severity, .safe)
        XCTAssertEqual(caution.severity, .caution)
        XCTAssertEqual(high.severity, .high)
        XCTAssertTrue(caution.requiresConfirmation)
        XCTAssertTrue(high.message.contains("swap heavily"))
    }

    func testMemoryAssessmentScalesWithContextConcurrencyAndLoadedModels() {
        let base = ControllerPolicy.memoryAssessment(modelBytes: [gib], contextSize: 4_096, physicalMemory: UInt64.max)
        let scaled = ControllerPolicy.memoryAssessment(modelBytes: [gib], contextSize: 8_192, parallelRequests: 2, loadedModelCount: 2, physicalMemory: UInt64.max)
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

@MainActor
final class ContextMemoryManagerTests: XCTestCase {
    private func makeManager(models: [DiscoveredModel] = [], physicalMemory: UInt64 = 36 * 1_073_741_824) -> (ServiceManager, FakeProbe, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        probe.discoveredModels = models
        probe.physicalMemory = physicalMemory
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return (ServiceManager(probe: probe, defaults: defaults, startTimer: false), probe, defaults)
    }

    func testLegacySavedContextIsNormalizedOnNextLoad() {
        let (manager, probe, defaults) = makeManager()
        var config = manager.configuration(for: .autocomplete)
        config.llama?.contextSize = 12_000
        manager.updateConfiguration(config, for: .autocomplete)
        let reloaded = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        XCTAssertEqual(reloaded.configuration(for: .autocomplete).llama?.contextSize, 8_192)
    }

    func testKnownInstalledCustomModelGetsVerifiedAssessment() {
        let model = DiscoveredModel(runtime: .llamaCpp, name: "custom", repository: "owner/repo", filename: "model.gguf", sizeBytes: 2_000_000_000, roleHint: .chat, supportsVision: false)
        let (manager, _, _) = makeManager(models: [model])
        var config = manager.configuration(for: .llamaChat)
        config.llama?.repository = "owner/repo"
        config.llama?.filename = "model.gguf"
        manager.updateConfiguration(config, for: .llamaChat)
        XCTAssertNotEqual(manager.memoryAssessment(for: .llamaChat).severity, .unverified)
    }

    func testCatalogMetadataIsUsedForAssessment() {
        let (manager, _, _) = makeManager()
        manager.updateRecommendationMetadata([
            ModelRecommendation(id: "catalog", name: "Catalog", source: "test", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 2_000_000_000, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil, repository: "owner/catalog", filename: "catalog.gguf")
        ])
        var config = manager.configuration(for: .llamaChat)
        config.llama?.repository = "owner/catalog"
        config.llama?.filename = "catalog.gguf"
        manager.updateConfiguration(config, for: .llamaChat)
        XCTAssertNotEqual(manager.memoryAssessment(for: .llamaChat).severity, .unverified)
    }

    func testUnsafeAndUnverifiedAssessmentsBecomeLaunchWarnings() {
        let (manager, _, _) = makeManager(physicalMemory: 15 * 1_073_741_824)
        XCTAssertTrue(manager.launchWarnings(for: [.llamaChat]).contains { $0.message.contains("safe budget") })
        var custom = manager.configuration(for: .autocomplete)
        custom.llama?.repository = "unknown/model"
        manager.updateConfiguration(custom, for: .autocomplete)
        XCTAssertTrue(manager.launchWarnings(for: [.autocomplete]).contains { $0.message.contains("unverified") })
    }
}
