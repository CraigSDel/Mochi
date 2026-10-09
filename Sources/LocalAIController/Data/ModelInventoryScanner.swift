import Foundation

/// Filesystem-backed inventory discovery. The scanner is used from detached
/// tasks by the model manager and never from an observable state path.
struct ModelInventoryScanner {
    let fileManager: FileManager
    let huggingFaceHubURL: URL

    init(
        fileManager: FileManager = .default,
        huggingFaceHubURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let home = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        self.huggingFaceHubURL = huggingFaceHubURL
            ?? environment["HF_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("hub") }
            ?? home.appendingPathComponent(".cache/huggingface/hub")
    }

    func scan() -> [DiscoveredModel] {
        scanHuggingFace().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanHuggingFace() -> [DiscoveredModel] {
        guard let repositories = try? fileManager.contentsOfDirectory(
            at: huggingFaceHubURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        var models: [DiscoveredModel] = []
        for repositoryURL in repositories where repositoryURL.lastPathComponent.hasPrefix("models--") {
            let encoded = String(repositoryURL.lastPathComponent.dropFirst("models--".count))
            let pieces = encoded.components(separatedBy: "--")
            guard pieces.count >= 2 else { continue }
            let repository = pieces[0] + "/" + pieces.dropFirst().joined(separator: "--")
            let snapshots = repositoryURL.appendingPathComponent("snapshots")
            guard let enumerator = fileManager.enumerator(
                at: snapshots,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            ) else { continue }
            var hasProjector = false
            var bases: [(label: String, filename: String, size: Int64?)] = []
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "gguf" {
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let filename = fileURL.lastPathComponent
                guard !filename.lowercased().contains("mmproj") else {
                    hasProjector = true
                    continue
                }
                let label = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                bases.append((label, filename, (attributes?[.size] as? NSNumber)?.int64Value))
            }
            models += bases.map {
                .init(
                    runtime: .llamaCpp,
                    name: $0.label,
                    repository: repository,
                    filename: $0.filename,
                    sizeBytes: $0.size,
                    roleHint: ModelCapability.role(inferringFrom: repository + " " + $0.filename),
                    supportsVision: hasProjector
                )
            }
        }
        return unique(models)
    }

    private func unique(_ models: [DiscoveredModel]) -> [DiscoveredModel] {
        var seen: Set<String> = []
        return models.filter { seen.insert($0.id).inserted }
    }
}
