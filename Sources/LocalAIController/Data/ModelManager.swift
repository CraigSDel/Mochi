import Foundation

final class ProbeModelManager: ModelManaging, @unchecked Sendable {
    private let probe: any SystemProbing
    init(probe: any SystemProbing) { self.probe = probe }
    func discover() async -> [DiscoveredModel] { await probe.discoverModels() }
    func loadMetadata() async -> [String: ModelMetadata] { [:] }
    func saveMetadata(_ metadata: [String: ModelMetadata]) async {}
    func download(_ recommendation: ModelRecommendation, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws { throw ModelManagementError.unsupportedSource }
    func delete(_ model: DiscoveredModel) async throws { throw ModelManagementError.unsupportedSource }
}

final class LiveModelManager: ModelManaging, @unchecked Sendable {
    private let inventory: any ModelInventoryProviding
    private let metadata: any ModelMetadataStoring
    private let transfer: any ModelTransferring

    init(
        fileManager: FileManager = .default,
        downloadClient: any ModelDownloadClient = URLSessionModelDownloadClient(),
        huggingFaceHubURL: URL? = nil,
        metadataURL: URL? = nil,
        inventory: (any ModelInventoryProviding)? = nil,
        metadata: (any ModelMetadataStoring)? = nil,
        transfer: (any ModelTransferring)? = nil
    ) {
        self.inventory = inventory ?? LiveModelInventorySource(
            fileManager: fileManager,
            huggingFaceHubURL: huggingFaceHubURL
        )
        self.metadata = metadata ?? FileModelMetadataStore(metadataURL: metadataURL)
        self.transfer = transfer ?? LiveModelTransferService(
            fileManager: fileManager,
            downloadClient: downloadClient,
            huggingFaceHubURL: huggingFaceHubURL
        )
    }

    func discover() async -> [DiscoveredModel] { await inventory.discover() }
    func loadMetadata() async -> [String: ModelMetadata] { await metadata.loadMetadata() }
    func saveMetadata(_ values: [String: ModelMetadata]) async { await metadata.saveMetadata(values) }
    func download(_ recommendation: ModelRecommendation, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws { try await transfer.download(recommendation, progress: progress) }
    func delete(_ model: DiscoveredModel) async throws { try await transfer.delete(model) }
}
