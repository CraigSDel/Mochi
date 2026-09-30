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
        XCTAssertEqual(models.count, 3)
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
            DiscoveredModel(runtime: .ollama, name: "general:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat),
            DiscoveredModel(runtime: .ollama, name: "code:latest", repository: nil, filename: nil, sizeBytes: 20, roleHint: .coding)
        ]
        let catalog = ModelRecommendation(id: "catalog", name: "embed", source: "Ollama Library", runtime: "Ollama", role: .embedding, quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown", compatibility: .unverified, rationale: "test", updatedAt: nil, modelName: "embed:latest")
        let options = ModelOptionBuilder.options(runtime: .ollama, role: .coding, installed: installed, recommendations: [catalog], currentOllamaName: "missing:latest")
        XCTAssertEqual(options.map(\.name), ["code:latest", "general:latest", "embed:latest", "missing:latest"])
        XCTAssertEqual(options.map(\.availability), [.installed, .installed, .catalog, .missing])
    }

    func testIncompatibleAndUnlaunchableCatalogItemsAreExcluded() {
        let blocked = ModelRecommendation(id: "blocked", name: "blocked", source: "HF", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .incompatible, rationale: "test", updatedAt: nil, repository: "owner/repo", filename: "model.gguf")
        let incomplete = ModelRecommendation(id: "incomplete", name: "incomplete", source: "HF", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil)
        XCTAssertTrue(ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: [], recommendations: [blocked, incomplete]).isEmpty)
    }

    func testInstalledOnlyExcludesCatalogForBothRuntimes() {
        let ollama = ModelRecommendation(id: "ollama", name: "ollama", source: "Fixture", runtime: "Ollama", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil, modelName: "ollama:latest")
        let llama = ModelRecommendation(id: "llama", name: "llama", source: "Fixture", runtime: "llama.cpp", role: .chat, quantization: "Q4", sizeBytes: 1, context: "test", license: "test", compatibility: .compatible, rationale: "test", updatedAt: nil, repository: "owner/llama", filename: "llama.gguf")

        XCTAssertTrue(ModelOptionBuilder.options(runtime: .ollama, role: .chat, installed: [], recommendations: [ollama], includeCatalog: false).isEmpty)
        XCTAssertTrue(ModelOptionBuilder.options(runtime: .llamaCpp, role: .chat, installed: [], recommendations: [llama], includeCatalog: false).isEmpty)
    }

    func testInstalledOnlyPreservesInstalledOrderingAndMissingCurrent() {
        let installed = [
            DiscoveredModel(runtime: .ollama, name: "general:latest", repository: nil, filename: nil, sizeBytes: 10, roleHint: .chat),
            DiscoveredModel(runtime: .ollama, name: "code:latest", repository: nil, filename: nil, sizeBytes: 20, roleHint: .coding)
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
