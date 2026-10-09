import Foundation

protocol ModelDownloadClient: Sendable {
  func download(from url: URL, progress: @escaping @Sendable (ModelDownloadProgress) -> Void)
    async throws -> ModelDownloadResult
}

struct ModelDownloadResult: Sendable {
  let temporaryURL: URL
  let statusCode: Int
}

struct URLSessionModelDownloadClient: ModelDownloadClient {
  func download(from url: URL, progress: @escaping @Sendable (ModelDownloadProgress) -> Void)
    async throws -> ModelDownloadResult
  {
    let bridge = URLSessionDownloadBridge(progress: progress)
    return try await withTaskCancellationHandler {
      try await bridge.download(from: url)
    } onCancel: {
      bridge.cancel()
    }
  }
}

private final class URLSessionDownloadBridge: NSObject, URLSessionDownloadDelegate,
  @unchecked Sendable
{
  private let progress: @Sendable (ModelDownloadProgress) -> Void
  private let lock = NSLock()
  private var session: URLSession?
  private var task: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<ModelDownloadResult, Error>?
  private var downloadedURL: URL?
  private var failure: Error?

  init(progress: @escaping @Sendable (ModelDownloadProgress) -> Void) {
    self.progress = progress
  }

  func download(from url: URL) async throws -> ModelDownloadResult {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      self.continuation = continuation
      let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
      self.session = session
      let task = session.downloadTask(with: url)
      self.task = task
      lock.unlock()
      task.resume()
    }
  }

  func cancel() {
    lock.lock()
    task?.cancel()
    lock.unlock()
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    progress(
      .init(
        completedBytes: totalBytesWritten,
        expectedBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      lock.lock()
      downloadedURL = destination
      lock.unlock()
    } catch {
      lock.lock()
      failure = error
      lock.unlock()
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    let resultURL = downloadedURL
    let failure = failure ?? error
    let statusCode = (task.response as? HTTPURLResponse)?.statusCode
    self.session = nil
    self.task = nil
    lock.unlock()

    if let failure {
      continuation?.resume(throwing: failure)
    } else if let resultURL, let statusCode {
      continuation?.resume(returning: .init(temporaryURL: resultURL, statusCode: statusCode))
    } else {
      continuation?.resume(
        throwing: ModelManagementError.downloadFailed(
          "The model download returned an invalid response."))
    }
  }
}
