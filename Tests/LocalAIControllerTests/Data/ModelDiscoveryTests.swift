import XCTest
@testable import LocalAIController

final class ModelInventoryScannerTests: XCTestCase {
    func testDiscoversOllamaAndHuggingFaceModels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ollama = root.appendingPathComponent("ollama")
        let manifest = ollama.appendingPathComponent("manifests/registry.ollama.ai/library/qwen-coder/7b")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"schemaVersion":2,"layers":[{"mediaType":"application/vnd.ollama.image.model","size":1234}]}"#.write(to: manifest, atomically: true, encoding: .utf8)
        let custom = ollama.appendingPathComponent("manifests/example.com/acme/embed-model/latest")
        try FileManager.default.createDirectory(at: custom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"schemaVersion":2,"layers":[]}"#.write(to: custom, atomically: true, encoding: .utf8)
        try "broken".write(to: custom.deletingLastPathComponent().appendingPathComponent("broken"), atomically: true, encoding: .utf8)

        let hub = root.appendingPathComponent("hub")
        let snapshot = hub.appendingPathComponent("models--owner--code-model/snapshots/revision")
        let blob = root.appendingPathComponent("blob.gguf")
        try Data(repeating: 1, count: 32).write(to: blob)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent("model-Q4_K_M.gguf"), withDestinationURL: blob)
        try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent("mmproj-model.gguf"), withDestinationURL: blob)

        let models = ModelInventoryScanner(fileManager: .default, ollamaModelsURL: ollama, huggingFaceHubURL: hub).scan()
        XCTAssertTrue(models.contains { $0.runtime == .ollama && $0.name == "qwen-coder:7b" && $0.sizeBytes == 1234 && $0.roleHint == .coding })
        XCTAssertTrue(models.contains { $0.runtime == .ollama && $0.name == "acme/embed-model:latest" && $0.roleHint == .embedding })
        XCTAssertTrue(models.contains { $0.runtime == .llamaCpp && $0.repository == "owner/code-model" && $0.filename == "model-Q4_K_M.gguf" })
        // The projector is not offered as a model; it marks the base GGUF instead.
        XCTAssertEqual(models.filter { $0.runtime == .llamaCpp }.count, 1)
        XCTAssertFalse(models.contains { $0.filename?.contains("mmproj") == true })
        XCTAssertEqual(models.first { $0.runtime == .llamaCpp }?.supportsVision, true)
        XCTAssertEqual(models.count, 3)
    }

    func testProjectorManifestLayerMarksOllamaModelAsVision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ollama = root.appendingPathComponent("ollama")
        let vision = ollama.appendingPathComponent("manifests/registry.ollama.ai/library/llava/latest")
        let text = ollama.appendingPathComponent("manifests/registry.ollama.ai/library/qwen3/8b")
        let adapter = ollama.appendingPathComponent("manifests/registry.ollama.ai/library/acme/lora/latest")
        try FileManager.default.createDirectory(at: vision.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: text.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapter.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"schemaVersion":2,"layers":[{"mediaType":"application/vnd.ollama.image.model","size":10},{"mediaType":"application/vnd.ollama.image.projector","size":20}]}"#.write(to: vision, atomically: true, encoding: .utf8)
        try #"{"schemaVersion":2,"layers":[{"mediaType":"application/vnd.ollama.image.model","size":10}]}"#.write(to: text, atomically: true, encoding: .utf8)
        // An adapter is a LoRA, not a vision projector.
        try #"{"schemaVersion":2,"layers":[{"mediaType":"application/vnd.ollama.image.adapter","size":10}]}"#.write(to: adapter, atomically: true, encoding: .utf8)

        let models = ModelInventoryScanner(fileManager: .default, ollamaModelsURL: ollama, huggingFaceHubURL: root.appendingPathComponent("hub")).scan()

        XCTAssertEqual(models.first { $0.name == "llava:latest" }?.supportsVision, true)
        XCTAssertEqual(models.first { $0.name == "qwen3:8b" }?.supportsVision, false)
        XCTAssertEqual(models.first { $0.name == "acme/lora:latest" }?.supportsVision, false)
    }

    func testHfSnapshotWithoutProjectorStaysTextOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let hub = root.appendingPathComponent("hub")
        let snapshot = hub.appendingPathComponent("models--owner--qwen3-gguf/snapshots/revision")
        let blob = root.appendingPathComponent("blob.gguf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: blob)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent("model-Q4_K_M.gguf"), withDestinationURL: blob)

        let models = ModelInventoryScanner(fileManager: .default, ollamaModelsURL: root.appendingPathComponent("ollama"), huggingFaceHubURL: hub).scan()

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].supportsVision, false)
    }

    func testMissingStoresReturnEmptyInventory() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scanner = ModelInventoryScanner(fileManager: .default, ollamaModelsURL: root.appendingPathComponent("ollama"), huggingFaceHubURL: root.appendingPathComponent("hub"))
        XCTAssertTrue(scanner.scan().isEmpty)
    }
}

final class ModelOptionBuilderTests: XCTestCase {
    func testInstalledRoleMatchesLeadAndCatalogFollows() {
        let installed = [
            DiscoveredModel(runtime: .ollama, name: "general:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat, supportsVision: false),
            DiscoveredModel(runtime: .ollama, name: "code:latest", repository: nil, filename: nil, sizeBytes: 20, roleHint: .coding, supportsVision: false)
        ]
        let catalog = ModelRecommendation(id: "catalog", name: "embed", source: "Ollama Library", runtime: "Ollama", role: .embedding, quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown", compatibility: .unverified, rationale: "test", updatedAt: nil, modelName: "embed:latest")
        let options = ModelOptionBuilder.options(runtime: .ollama, role: .coding, installed: installed, recommendations: [catalog], currentOllamaName: "missing:latest")
        XCTAssertEqual(options.map(\.name), ["code:latest", "general:latest", "embed:latest", "missing:latest"])
        XCTAssertEqual(options.map(\.availability), [.installed, .installed, .catalog, .missing])
    }

    func testTaglessCatalogNameDoesNotDuplicateTheInstalledModel() {
        let installed = [DiscoveredModel(runtime: .ollama, name: "llava:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat, supportsVision: false)]
        let catalog = ModelRecommendation(id: "ollama:llava", name: "llava", source: "Ollama Library", runtime: "Ollama", role: .chat, quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown", compatibility: .unverified, rationale: "test", updatedAt: nil, modelName: "llava")

        let options = ModelOptionBuilder.options(runtime: .ollama, role: .chat, installed: installed, recommendations: [catalog], currentOllamaName: "llava")

        XCTAssertEqual(options.map(\.name), ["llava:latest"])
        XCTAssertEqual(options.map(\.availability), [.installed])
    }

    func testConfiguredTaglessNameResolvesToTheInstalledModel() {
        let installed = [DiscoveredModel(runtime: .ollama, name: "llava:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat, supportsVision: false)]

        let options = ModelOptionBuilder.options(runtime: .ollama, role: .chat, installed: installed, recommendations: [], currentOllamaName: "llava")

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].id, "ollama:llava:latest")
        XCTAssertEqual(options[0].availability, .installed)
    }

    func testVisionModelsAreExcludedButAnAssignedOneStillSurfaces() {
        let installed = [
            DiscoveredModel(runtime: .ollama, name: "llava:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat, supportsVision: true),
            DiscoveredModel(runtime: .ollama, name: "qwen3:8b", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat, supportsVision: false)
        ]

        let unassigned = ModelOptionBuilder.options(runtime: .ollama, role: .chat, installed: installed, recommendations: [], currentOllamaName: nil)
        XCTAssertEqual(unassigned.map(\.name), ["qwen3:8b"])

        let assigned = ModelOptionBuilder.options(runtime: .ollama, role: .chat, installed: installed, recommendations: [], currentOllamaName: "llava")
        XCTAssertEqual(assigned.map(\.name), ["qwen3:8b", "llava"])
        XCTAssertEqual(assigned.last?.availability, .unsupported)
    }

    func testInstalledLlamaProjectorIsExcludedFromThePicker() {
        let installed = [DiscoveredModel(runtime: .llamaCpp, name: "mmproj", repository: "owner/llava-gguf", filename: "model-Q4_K_M.gguf", sizeBytes: 10, roleHint: .chat, supportsVision: true)]
        let current = LlamaLaunchConfiguration(repository: "owner/llava-gguf", filename: "model-Q4_K_M.gguf", alias: "llava", contextSize: 4096, gpuLayers: 99)

        XCTAssertTrue(ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: installed, recommendations: [], currentLlama: nil).isEmpty)
        let assigned = ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: installed, recommendations: [], currentLlama: current)
        XCTAssertEqual(assigned.map(\.availability), [.unsupported])
    }

    func testIncompatibleAndUnlaunchableCatalogItemsAreExcluded() {
        let blocked = ModelRecommendation(id: "blocked", name: "blocked", source: "HF", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .incompatible, rationale: "test", updatedAt: nil, repository: "owner/repo", filename: "model.gguf")
        let incomplete = ModelRecommendation(id: "incomplete", name: "incomplete", source: "HF", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil)
        XCTAssertTrue(ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: [], recommendations: [blocked, incomplete]).isEmpty)
    }

    func testQueuedHuggingFaceRecommendationAppearsInLlamaPicker() {
        let queued = ModelRecommendation(
            id: "hf:owner/queued", name: "owner/queued", source: "Hugging Face", runtime: "llama.cpp", role: .chat,
            quantization: "Q4_K_M", sizeBytes: 1, context: "test", license: "test",
            compatibility: .compatible, rationale: "queued", updatedAt: nil,
            repository: "owner/queued", filename: "queued-Q4_K_M.gguf"
        )

        let options = ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: [], recommendations: [queued])

        XCTAssertEqual(options.map(\.name), ["owner/queued"])
        XCTAssertEqual(options.first?.availability, .catalog)
    }

    func testInstalledOnlyExcludesCatalogForBothRuntimes() {
        let ollama = ModelRecommendation(id: "ollama", name: "ollama", source: "Fixture", runtime: "Ollama", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil, modelName: "ollama:latest")
        let llama = ModelRecommendation(id: "llama", name: "llama", source: "Fixture", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil, repository: "owner/llama", filename: "llama.gguf")

        XCTAssertTrue(ModelOptionBuilder.options(runtime: .ollama, role: .chat, installed: [], recommendations: [ollama], includeCatalog: false).isEmpty)
        XCTAssertTrue(ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: [], recommendations: [llama], includeCatalog: false).isEmpty)
    }

    func testInstalledOnlyPreservesInstalledOrderingAndMissingCurrent() {
        let installed = [
            DiscoveredModel(runtime: .ollama, name: "general:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat, supportsVision: false),
            DiscoveredModel(runtime: .ollama, name: "code:latest", repository: nil, filename: nil, sizeBytes: 20, roleHint: .coding, supportsVision: false)
        ]

        let options = ModelOptionBuilder.options(runtime: .ollama, role: .coding, installed: installed, recommendations: [], currentOllamaName: "missing:latest", includeCatalog: false)

        XCTAssertEqual(options.map(\.name), ["code:latest", "general:latest", "missing:latest"])
        XCTAssertEqual(options.map(\.availability), [.installed, .installed, .missing])
    }

    func testCatalogPreferenceKeysAreUniquePerService() {
        let keys = ServiceID.allCases.map(ModelCatalogPreferences.key)
        XCTAssertEqual(Set(keys).count, ServiceID.allCases.count)
    }
}
