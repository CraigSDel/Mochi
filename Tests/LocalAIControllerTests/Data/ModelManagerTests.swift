import XCTest
@testable import LocalAIController

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

        try await manager.download(recommendation)

        let destination = hub.appendingPathComponent("models--org--model/snapshots/manual/model.gguf")
        XCTAssertEqual(try Data(contentsOf: destination), Data("model".utf8))
        let requestedURL = await client.requestedURL
        XCTAssertEqual(requestedURL?.absoluteString, "https://huggingface.co/org/model/resolve/main/model.gguf?download=true")
    }
}

private actor StubModelDownloadClient: ModelDownloadClient {
    let result: ModelDownloadResult
    private(set) var requestedURL: URL?

    init(result: ModelDownloadResult) {
        self.result = result
    }

    func download(from url: URL) async throws -> ModelDownloadResult {
        requestedURL = url
        return result
    }
}
