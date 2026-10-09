import XCTest
@testable import LocalAIController

final class PerformanceTuningTests: XCTestCase {
    func testLegacyLlamaConfigurationDecodesWithTuningDefaults() throws {
        let json = #"{"repository":"owner/model","filename":"model.gguf","alias":"Model","contextSize":8192,"gpuLayers":99}"#.data(using: .utf8)!
        let configuration = try JSONDecoder().decode(LlamaLaunchConfiguration.self, from: json)
        XCTAssertEqual(configuration.cacheReuse, 256)
        XCTAssertEqual(configuration.kvCacheKeyType, "q8_0")
        XCTAssertEqual(configuration.generation, .balanced)
    }

    func testLegacyOllamaConfigurationDecodesWithGenerationDefaults() throws {
        let json = #"{"chatModel":"chat","autocompleteModel":"code","embeddingModel":"embed","flashAttention":true,"kvCacheType":"q8_0","contextLength":16384,"parallelRequests":2,"maxLoadedModels":1}"#.data(using: .utf8)!
        let configuration = try JSONDecoder().decode(OllamaLaunchConfiguration.self, from: json)
        XCTAssertEqual(configuration.chatGeneration, .balanced)
        XCTAssertEqual(configuration.autocompleteGeneration, .autocompleteBalanced)
    }

    func testPresetsRestoreDeterministicLlamaBaseline() {
        let base = ServiceLaunchConfiguration.defaultValue(for: .llamaChat).llama!
        let fast = PerformancePresetMapper.llama(base, preset: .fast, baselineContext: 16_384)
        let restored = PerformancePresetMapper.llama(fast, preset: .balanced, baselineContext: 16_384)
        XCTAssertEqual(fast.contextSize, 8_192)
        XCTAssertEqual(restored.contextSize, 16_384)
        XCTAssertEqual(restored.generation, .balanced)
    }

    func testQualityOllamaPresetRaisesThroughputAndContextLimits() {
        let base = ServiceLaunchConfiguration.defaultValue(for: .ollama).ollama!
        let quality = PerformancePresetMapper.ollama(base, preset: .quality)
        XCTAssertEqual(quality.contextLength, 32_768)
        XCTAssertEqual(quality.parallelRequests, 4)
        XCTAssertEqual(quality.maxLoadedModels, 2)
    }

    func testAggressiveCacheReuseRaisesMemoryEstimate() {
        let normal = ControllerPolicy.memoryAssessment(modelBytes: [1_000_000], contextSize: 8_192, physicalMemory: UInt64.max)
        let aggressive = ControllerPolicy.memoryAssessment(modelBytes: [1_000_000], contextSize: 8_192, cacheReuse: 512, physicalMemory: UInt64.max)
        XCTAssertGreaterThan(aggressive.estimatedBytes!, normal.estimatedBytes!)
    }

    func testProviderExportIncludesRoleEndpointsAndGeneration() throws {
        let configurations = Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { ($0, ServiceLaunchConfiguration.defaultValue(for: $0)) })
        let records = ProviderExportBuilder.records(configurations: configurations)
        XCTAssertEqual(records["llamaChat"]?.type, "chat")
        XCTAssertEqual(records["autocomplete"]?.apiPath, "/completion")
        XCTAssertEqual(records["embeddings"]?.type, "embedding")
        XCTAssertEqual(records["llamaChat"]?.maxOutputTokens, 1_024)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: ProviderExportBuilder.data(configurations: configurations)))
    }
}

@MainActor
final class PerformanceTuningValidationTests: XCTestCase {
    func testInvalidTuningProducesFieldSpecificIssues() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = ServiceManager(probe: probe, defaults: defaults, startTimer: false)
        var configuration = manager.configuration(for: .llamaChat)
        configuration.llama?.cacheReuse = 9_999; configuration.llama?.generation.topP = 2
        manager.updateConfiguration(configuration, for: .llamaChat)
        let issues = manager.validationIssues(for: .llamaChat)
        XCTAssertTrue(issues.contains { $0.field == "cacheReuse" })
        XCTAssertTrue(issues.contains { $0.field == "generation.topP" })
    }

    func testOllamaRequestGenerationTuningIsRejectedByLauncherValidation() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = ServiceManager(probe: FakeProbe(directory: directory), defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        var configuration = manager.configuration(for: .ollama)
        configuration.ollama?.chatGeneration.temperature = 0.2
        manager.updateConfiguration(configuration, for: .ollama)
        XCTAssertTrue(manager.validationIssues(for: .ollama).contains { $0.field == "generation" && $0.message.contains("not supported") })
    }
}
