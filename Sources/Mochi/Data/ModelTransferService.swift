import Foundation

final class LiveModelTransferService: ModelTransferring, @unchecked Sendable {
  private let fileManager: FileManager
  private let downloadClient: any ModelDownloadClient
  private let huggingFaceHubURL: URL

  init(fileManager: FileManager, downloadClient: any ModelDownloadClient, huggingFaceHubURL: URL?) {
    self.fileManager = fileManager
    self.downloadClient = downloadClient
    self.huggingFaceHubURL =
      huggingFaceHubURL
      ?? ProcessInfo.processInfo.environment["HF_HOME"].map {
        URL(fileURLWithPath: $0).appendingPathComponent("hub")
      }
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
  }

  func download(
    _ recommendation: ModelRecommendation,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    guard let repository = recommendation.repository, let filename = recommendation.filename,
      validComponent(repository), validComponent(filename)
    else { throw ModelManagementError.invalidModelIdentity }
    let executable = URL(
      string: "https://huggingface.co/\(repository)/resolve/main/\(filename)?download=true")!
    let destinationRoot = huggingFaceHubURL.appendingPathComponent(
      "models--\(repository.replacingOccurrences(of: "/", with: "--"))")
    let snapshot = destinationRoot.appendingPathComponent("snapshots/manual")
    let destination = snapshot.appendingPathComponent(filename)
    let result = try await downloadClient.download(from: executable, progress: progress)
    guard result.statusCode == 200 else {
      throw ModelManagementError.downloadFailed(
        "The model download returned HTTP \(result.statusCode). Check the repository and filename, then try again."
      )
    }
    try await Task.detached(priority: .utility) { [fileManager, temporary = result.temporaryURL] in
      try fileManager.createDirectory(at: snapshot, withIntermediateDirectories: true)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: temporary, to: destination)
    }.value
  }

  func delete(_ model: DiscoveredModel) async throws {
    guard let repository = model.repository, let filename = model.filename,
      validComponent(repository), validComponent(filename)
    else { throw ModelManagementError.invalidModelIdentity }
    let root = huggingFaceHubURL.appendingPathComponent(
      "models--\(repository.replacingOccurrences(of: "/", with: "--"))"
    ).standardizedFileURL
    try await Task.detached(priority: .utility) { [fileManager] in
      guard
        let enumerator = fileManager.enumerator(
          at: root, includingPropertiesForKeys: [.isRegularFileKey])
      else { throw ModelManagementError.unsafePath }
      let matches = enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent == filename }
      guard !matches.isEmpty,
        matches.allSatisfy({ $0.standardizedFileURL.path.hasPrefix(root.path + "/") })
      else { throw ModelManagementError.unsafePath }
      for match in matches { try fileManager.removeItem(at: match) }
      let remaining = matches.map { $0.deletingLastPathComponent() }.filter {
        fileManager.fileExists(atPath: $0.path)
      }
      for directory in Set(remaining) {
        let files =
          (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        let hasBaseModel = files.contains {
          $0.pathExtension.lowercased() == "gguf"
            && !$0.lastPathComponent.lowercased().contains("mmproj")
        }
        if !hasBaseModel {
          for projector in files where projector.lastPathComponent.lowercased().contains("mmproj") {
            try? fileManager.removeItem(at: projector)
          }
        }
      }
    }.value
  }

  private func validComponent(_ value: String) -> Bool {
    !value.isEmpty && !value.contains("..") && !value.contains("\\") && !value.hasPrefix("/")
  }
}
