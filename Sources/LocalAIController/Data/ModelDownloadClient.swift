import Foundation

protocol ModelDownloadClient: Sendable {
    func download(from url: URL) async throws -> ModelDownloadResult
}

struct ModelDownloadResult: Sendable {
    let temporaryURL: URL
    let statusCode: Int
}

struct URLSessionModelDownloadClient: ModelDownloadClient {
    func download(from url: URL) async throws -> ModelDownloadResult {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelManagementError.downloadFailed("The model download returned an invalid response.")
        }
        return ModelDownloadResult(temporaryURL: temporaryURL, statusCode: httpResponse.statusCode)
    }
}
