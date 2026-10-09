import XCTest
@testable import Mochi

final class ModelManagerTests: XCTestCase {
    func test_downloadUsesInjectedClientAndMovesFileIntoManagedSnapshot() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let temporary = root.appendingPathComponent("temporary.gguf")
        let hub = root.appendingPathComponent("hub")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: temporary)

        let client = StubModelDownloadClient(result: .init(temporaryURL: temporary, statusCode: 200))
        let manager = LiveModelManager(
            fileManager: fileManager,
            downloadClient: client,
            huggingFaceHubURL: hub
        )
        let recommendation = ModelRecommendation(
            id: "hf-test",
            name: "Test model",
            source: "Hugging Face",
            runtime: "llama.cpp",
            role: .chat,
            quantization: "Q4_K_M",
            sizeBytes: nil,
            context: "8K",
            license: "MIT",
            compatibility: .compatible,
            rationale: "Test",
            updatedAt: nil,
            repository: "org/model",
            filename: "model.gguf"
        )

        try await manager.download(recommendation, progress: { _ in })

        let destination = hub.appendingPathComponent("models--org--model/snapshots/manual/model.gguf")
        XCTAssertEqual(try Data(contentsOf: destination), Data("model".utf8))
        let requestedURL = await client.requestedURL
        XCTAssertEqual(requestedURL?.absoluteString, "https://huggingface.co/org/model/resolve/main/model.gguf?download=true")
    }

    func test_downloadReportsInjectedProgress() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let temporary = root.appendingPathComponent("temporary.gguf")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: temporary)

        let client = StubModelDownloadClient(result: .init(temporaryURL: temporary, statusCode: 200))
        let manager = LiveModelManager(fileManager: fileManager, downloadClient: client, huggingFaceHubURL: root.appendingPathComponent("hub"))
        let recommendation = ModelRecommendation(
            id: "hf-progress", name: "Test", source: "Hugging Face", runtime: "llama.cpp", role: .chat,
            quantization: "Q4", sizeBytes: 100, context: "test", license: "MIT",
            compatibility: .compatible, rationale: "test", updatedAt: nil,
            repository: "org/model", filename: "model.gguf"
        )
        let progress = ProgressRecorder()

        try await manager.download(recommendation) { progress.append($0) }

        XCTAssertEqual(progress.values.map(\.completedBytes), [50])
        XCTAssertEqual(progress.values.first?.fractionCompleted, 0.5)
    }

    func test_downloadReportsHTTPFailureWithStatusAndGuidance() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let client = StubModelDownloadClient(result: .init(temporaryURL: root, statusCode: 404))
        let manager = LiveModelManager(fileManager: fileManager, downloadClient: client, huggingFaceHubURL: root)
        let recommendation = ModelRecommendation(
            id: "hf-http", name: "Missing", source: "Hugging Face", runtime: "llama.cpp", role: .chat,
            quantization: "Q4", sizeBytes: nil, context: "test", license: "MIT",
            compatibility: .compatible, rationale: "test", updatedAt: nil,
            repository: "org/model", filename: "missing.gguf"
        )

        do {
            try await manager.download(recommendation, progress: { _ in })
            XCTFail("Expected HTTP failure")
        } catch let error as ModelManagementError {
            XCTAssertEqual(error.errorDescription, "The model download returned HTTP 404. Check the repository and filename, then try again.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_metadataStore_roundTripsAssignments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileModelMetadataStore(metadataURL: root.appendingPathComponent("metadata.json"))
        let values = ["model": ModelMetadata(alias: "Model", role: .chat, assignedServices: [.llamaChat], isPinned: true)]

        await store.saveMetadata(values)

        let loaded = await store.loadMetadata()
        XCTAssertEqual(loaded, values)
    }

    func test_deleteRejectsMissingManagedModelPath() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = LiveModelManager(fileManager: .default, huggingFaceHubURL: root)
        let model = DiscoveredModel(
            runtime: .llamaCpp, name: "missing", repository: "org/model", filename: "missing.gguf",
            sizeBytes: nil, roleHint: .chat, supportsVision: false
        )

        do {
            try await manager.delete(model)
            XCTFail("Expected unsafe path rejection")
        } catch let error as ModelManagementError {
            XCTAssertEqual(error, .unsafePath)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [ModelDownloadProgress] = []

    func append(_ value: ModelDownloadProgress) {
        lock.lock(); values.append(value); lock.unlock()
    }
}

private actor StubModelDownloadClient: ModelDownloadClient {
    let result: ModelDownloadResult
    private(set) var requestedURL: URL?

    init(result: ModelDownloadResult) {
        self.result = result
    }

    func download(from url: URL, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws -> ModelDownloadResult {
        requestedURL = url
        progress(.init(completedBytes: 50, expectedBytes: 100))
        return result
    }
}
