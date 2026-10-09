// Tests/LocalAIControllerTests/Application/ContextMemoryManagerTests.swift
import XCTest
@testable import LocalAIController

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

    func testKnownInstalledCustomModelGetsVerifiedAssessment() async {
        let model = DiscoveredModel(runtime: .llamaCpp, name: "custom", repository: "owner/repo", filename: "model.gguf", sizeBytes: 2_000_000_000, roleHint: .chat, supportsVision: false)
        let (manager, _, _) = makeManager(models: [model])
        await manager.refreshModelInventory()
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

    func testOllamaGuidanceMatchesLaunchAssessment() {
        let models = [
            DiscoveredModel(runtime: .ollama, name: "qwen3:27b", repository: nil, filename: nil, sizeBytes: 16 * 1_073_741_824, roleHint: .chat, supportsVision: false),
            DiscoveredModel(runtime: .ollama, name: "qwen2.5-coder:1.5b", repository: nil, filename: nil, sizeBytes: 2 * 1_073_741_824, roleHint: .chat, supportsVision: false),
            DiscoveredModel(runtime: .ollama, name: "nomic-embed-text:v1.5", repository: nil, filename: nil, sizeBytes: 1 * 1_073_741_824, roleHint: .embedding, supportsVision: false)
        ]
        let (manager, _, _) = makeManager(models: models)
        var configuration = manager.configuration(for: .ollama)
        configuration.ollama?.maxLoadedModels = 1
        manager.updateConfiguration(configuration, for: .ollama)

        let guidance = manager.performanceGuidance().first { $0.runtime == .ollama }
        XCTAssertEqual(guidance?.severity.rawValue, manager.memoryAssessment(for: .ollama).severity.rawValue)
    }
}
