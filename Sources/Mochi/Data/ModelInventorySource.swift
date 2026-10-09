import Foundation

final class LiveModelInventorySource: ModelInventoryProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let huggingFaceHubURL: URL?

    init(fileManager: FileManager, huggingFaceHubURL: URL?) {
        self.fileManager = fileManager
        self.huggingFaceHubURL = huggingFaceHubURL
    }

    func discover() async -> [DiscoveredModel] {
        await Task.detached(priority: .utility) { [fileManager, huggingFaceHubURL] in
            ModelInventoryScanner(
                fileManager: fileManager,
                huggingFaceHubURL: huggingFaceHubURL
            ).scan()
        }.value
    }
}

actor FileModelMetadataStore: ModelMetadataStoring {
    private let metadataURL: URL

    init(metadataURL: URL?) {
        self.metadataURL = metadataURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mochi/model-metadata.json")
    }

    func loadMetadata() async -> [String: ModelMetadata] {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([String: ModelMetadata].self, from: data) else { return [:] }
        return metadata
    }

    func saveMetadata(_ metadata: [String: ModelMetadata]) async {
        try? FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}
