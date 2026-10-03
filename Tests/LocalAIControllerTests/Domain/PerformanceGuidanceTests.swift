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

    func testHighContextLengthRaisesSeverity() {
        let guidance = PerformanceGuidance.make(
            runtime: .ollama,
            modelLabel: "Large model",
            modelBytes: [16 * gib],
            quantization: nil,
            contextSize: 131_072,
            parallelRequests: 2,
            loadedModelCount: 1,
            kvCacheType: "q8_0",
            physicalMemory: memory
        )

        XCTAssertEqual(guidance.severity, .high)
        XCTAssertTrue(guidance.recommendations.contains { $0.contains("Ollama KV cache: q8_0") })
    }

    func testMissingMetadataIsExplicitlyUnverified() {
        let guidance = PerformanceGuidance.make(
            runtime: .ollama,
            modelLabel: "Unknown",
            modelBytes: nil,
            quantization: nil,
            contextSize: 16_384,
            kvCacheType: "q4_0",
            physicalMemory: memory
        )

        XCTAssertEqual(guidance.severity, .unverified)
        XCTAssertTrue(guidance.summary.contains("unverified"))
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

    func testOllamaSelectionDeduplicatesNormalizedNames() {
        let configuration = ollamaConfiguration(
            chatModel: "qwen3:latest",
            autocompleteModel: "qwen3",
            embeddingModel: "nomic-embed-text:v1.5",
            maxLoadedModels: 2
        )
        let selection = OllamaMemoryModelSelection.resolve(
            configuration: configuration,
            installedModels: [
                ollamaModel("qwen3:latest", size: 8 * gib),
                ollamaModel("nomic-embed-text:v1.5", size: 2 * gib)
            ],
            recommendations: [],
            isDefaultConfiguration: false,
            defaultSize: nil
        )

        XCTAssertEqual(selection.loadedModelCount, 2)
        XCTAssertEqual(selection.modelBytes, [8 * gib, 2 * gib])
    }

    func testOllamaSelectionUsesOnlyLargestLoadedModels() {
        let configuration = ollamaConfiguration(maxLoadedModels: 1)
        let selection = OllamaMemoryModelSelection.resolve(
            configuration: configuration,
            installedModels: [
                ollamaModel(configuration.chatModel, size: 16 * gib),
                ollamaModel(configuration.autocompleteModel, size: 2 * gib),
                ollamaModel(configuration.embeddingModel, size: 1 * gib)
            ],
            recommendations: [],
            isDefaultConfiguration: false,
            defaultSize: nil
        )

        XCTAssertEqual(selection.loadedModelCount, 1)
        XCTAssertEqual(selection.modelBytes, [16 * gib])
    }

    private func ollamaConfiguration(
        chatModel: String = "qwen3:27b",
        autocompleteModel: String = "qwen2.5-coder:1.5b",
        embeddingModel: String = "nomic-embed-text:v1.5",
        maxLoadedModels: Int
    ) -> OllamaLaunchConfiguration {
        .init(
            chatModel: chatModel,
            autocompleteModel: autocompleteModel,
            embeddingModel: embeddingModel,
            flashAttention: true,
            kvCacheType: "q8_0",
            contextLength: 16_384,
            parallelRequests: 1,
            maxLoadedModels: maxLoadedModels
        )
    }

    private func ollamaModel(_ name: String, size: Int64) -> DiscoveredModel {
        .init(runtime: .ollama, name: name, repository: nil, filename: nil, sizeBytes: size, roleHint: .chat, supportsVision: false)
    }
}
