import Foundation

final class ProbeModelManager: ModelManaging, @unchecked Sendable {
    private let probe: any SystemProbing

    init(probe: any SystemProbing) { self.probe = probe }
    func discover() async -> [DiscoveredModel] { await probe.discoverModels() }
    func loadMetadata() async -> [String: ModelMetadata] { [:] }
    func saveMetadata(_ metadata: [String: ModelMetadata]) async {}
    func download(_ recommendation: ModelRecommendation) async throws { throw ModelManagementError.unsupportedSource }
    func delete(_ model: DiscoveredModel) async throws { throw ModelManagementError.unsupportedSource }
}

final class LiveModelManager: ModelManaging, @unchecked Sendable {
    private let fileManager: FileManager
    private let metadataURL: URL
    private let ollamaModelsURL: URL
    private let huggingFaceHubURL: URL
    private let downloadClient: any ModelDownloadClient

    init(
        fileManager: FileManager = .default,
        downloadClient: any ModelDownloadClient = URLSessionModelDownloadClient(),
        ollamaModelsURL: URL? = nil,
        huggingFaceHubURL: URL? = nil,
        metadataURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.downloadClient = downloadClient
        let home = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        self.ollamaModelsURL = ollamaModelsURL
            ?? environment["OLLAMA_MODELS"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".ollama/models")
        self.huggingFaceHubURL = huggingFaceHubURL
            ?? environment["HF_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("hub") }
            ?? home.appendingPathComponent(".cache/huggingface/hub")
        self.metadataURL = metadataURL
            ?? home.appendingPathComponent("Library/Application Support/Local AI Controller/model-metadata.json")
    }

    func discover() async -> [DiscoveredModel] {
        await Task.detached(priority: .utility) { [fileManager, ollamaModelsURL, huggingFaceHubURL] in
            ModelInventoryScanner(fileManager: fileManager, ollamaModelsURL: ollamaModelsURL, huggingFaceHubURL: huggingFaceHubURL).scan()
        }.value
    }

    func loadMetadata() async -> [String: ModelMetadata] {
        await Task.detached(priority: .utility) { [metadataURL] in
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode([String: ModelMetadata].self, from: data) else { return [:] }
            return metadata
        }.value
    }

    func saveMetadata(_ metadata: [String: ModelMetadata]) async {
        await Task.detached(priority: .utility) { [fileManager, metadataURL] in
            try? fileManager.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(metadata) else { return }
            try? data.write(to: metadataURL, options: .atomic)
        }.value
    }

    func download(_ recommendation: ModelRecommendation) async throws {
        if recommendation.runtime.caseInsensitiveCompare("Ollama") == .orderedSame {
            try await run("ollama", arguments: ["pull", recommendation.modelName ?? recommendation.name])
            return
        }
        guard let repository = recommendation.repository, let filename = recommendation.filename,
              validComponent(repository), validComponent(filename) else { throw ModelManagementError.invalidModelIdentity }
        let executable = URL(string: "https://huggingface.co/\(repository)/resolve/main/\(filename)?download=true")!
        let destinationRoot = huggingFaceHubURL.appendingPathComponent("models--\(repository.replacingOccurrences(of: "/", with: "--"))")
        let snapshot = destinationRoot.appendingPathComponent("snapshots/manual")
        let destination = snapshot.appendingPathComponent(filename)
        let result = try await downloadClient.download(from: executable)
        guard result.statusCode == 200 else {
            throw ModelManagementError.downloadFailed("The model download returned an unsuccessful response.")
        }
        try await Task.detached(priority: .utility) { [fileManager, temporary = result.temporaryURL] in
            try fileManager.createDirectory(at: snapshot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporary, to: destination)
        }.value
    }

    func delete(_ model: DiscoveredModel) async throws {
        switch model.runtime {
        case .ollama:
            try await run("ollama", arguments: ["rm", model.name])
        case .llamaCpp:
            guard let repository = model.repository, let filename = model.filename,
                  validComponent(repository), validComponent(filename) else { throw ModelManagementError.invalidModelIdentity }
            let root = huggingFaceHubURL.appendingPathComponent("models--\(repository.replacingOccurrences(of: "/", with: "--"))").standardizedFileURL
            try await Task.detached(priority: .utility) { [fileManager] in
                guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { throw ModelManagementError.unsafePath }
                let matches = enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent == filename }
                guard !matches.isEmpty, matches.allSatisfy({ $0.standardizedFileURL.path.hasPrefix(root.path + "/") }) else { throw ModelManagementError.unsafePath }
                for match in matches { try fileManager.removeItem(at: match) }
                let remaining = matches.map { $0.deletingLastPathComponent() }.filter { fileManager.fileExists(atPath: $0.path) }
                for directory in Set(remaining) {
                    let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
                    let hasBaseModel = files.contains { $0.pathExtension.lowercased() == "gguf" && !$0.lastPathComponent.lowercased().contains("mmproj") }
                    if !hasBaseModel {
                        for projector in files where projector.lastPathComponent.lowercased().contains("mmproj") { try? fileManager.removeItem(at: projector) }
                    }
                }
            }.value
        }
    }

    private func run(_ command: String, arguments: [String]) async throws {
        guard let executable = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].lazy.map({ URL(fileURLWithPath: $0).appendingPathComponent(command).path }).first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw ModelManagementError.runtimeUnavailable(command)
        }
        let result = await Task.detached(priority: .utility) {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = pipe; process.standardError = pipe
            do { try process.run() } catch { return (1, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (Int(process.terminationStatus), String(data: data, encoding: .utf8) ?? "")
        }.value
        guard result.0 == 0 else { throw ModelManagementError.commandFailed(result.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func validComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("..") && !value.contains("\\") && !value.hasPrefix("/")
    }
}
