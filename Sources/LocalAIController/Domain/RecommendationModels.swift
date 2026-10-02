import Foundation

enum RecommendationRole: String, Codable, CaseIterable, Sendable {
    case chat = "Chat / reasoning"
    case coding = "Coding / autocomplete"
    case embedding = "Embeddings"
}

enum ModelRuntime: String, Codable, Sendable {
    case llamaCpp
    case ollama
}

struct DiscoveredModel: Identifiable, Hashable, Sendable {
    let runtime: ModelRuntime
    let name: String
    let repository: String?
    let filename: String?
    let sizeBytes: Int64?
    let roleHint: RecommendationRole
    /// Detected from local metadata only: an Ollama projector manifest layer, or
    /// an `mmproj-*.gguf` sibling in a Hugging Face snapshot.
    let supportsVision: Bool

    var id: String {
        switch runtime {
        case .llamaCpp: "llama:\(repository ?? ""):\(filename ?? name)"
        case .ollama: "ollama:\(name)"
        }
    }
}

enum ModelAvailability: String, Sendable {
    case installed = "Installed"
    case catalog = "Download required"
    case custom = "Custom"
    case missing = "Unavailable"
    case unsupported = "Multimodal (not supported)"
}

struct ModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let runtime: ModelRuntime
    let name: String
    let repository: String?
    let filename: String?
    let sizeBytes: Int64?
    let roleHint: RecommendationRole
    let availability: ModelAvailability

    var detail: String {
        let size = sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [availability.rawValue, size, roleHint.rawValue].compactMap { $0 }.joined(separator: " · ")
    }
}

enum Compatibility: String, Codable, Sendable {
    case compatible = "Compatible"
    case unverified = "Unverified"
    case incompatible = "Incompatible"
}

enum RecommendationCompatibilityFilter: String, Codable, CaseIterable, Sendable {
    case all
    case compatibleOnly

    func includes(_ recommendation: ModelRecommendation) -> Bool {
        self == .all || recommendation.compatibility == .compatible
    }

    func apply(to recommendations: [ModelRecommendation], role: RecommendationRole? = nil) -> [ModelRecommendation] {
        recommendations.filter { recommendation in
            includes(recommendation) && (role == nil || recommendation.role == role)
        }
    }
}

struct ModelRecommendation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let source: String
    let runtime: String
    let role: RecommendationRole
    let quantization: String
    let sizeBytes: Int64?
    let context: String
    let license: String
    let compatibility: Compatibility
    let rationale: String
    let updatedAt: Date?
    let repository: String?
    let filename: String?
    let modelName: String?

    init(
        id: String, name: String, source: String, runtime: String, role: RecommendationRole,
        quantization: String, sizeBytes: Int64?, context: String, license: String,
        compatibility: Compatibility, rationale: String, updatedAt: Date?,
        repository: String? = nil, filename: String? = nil, modelName: String? = nil
    ) {
        self.id = id; self.name = name; self.source = source; self.runtime = runtime; self.role = role
        self.quantization = quantization; self.sizeBytes = sizeBytes; self.context = context; self.license = license
        self.compatibility = compatibility; self.rationale = rationale; self.updatedAt = updatedAt
        self.repository = repository; self.filename = filename; self.modelName = modelName
    }
    var sizeText: String {
        guard let sizeBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct ModelInventoryScanner {
    let fileManager: FileManager
    let ollamaModelsURL: URL
    let huggingFaceHubURL: URL

    init(
        fileManager: FileManager = .default,
        ollamaModelsURL: URL? = nil,
        huggingFaceHubURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let home = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        self.ollamaModelsURL = ollamaModelsURL
            ?? environment["OLLAMA_MODELS"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".ollama/models")
        self.huggingFaceHubURL = huggingFaceHubURL
            ?? environment["HF_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("hub") }
            ?? home.appendingPathComponent(".cache/huggingface/hub")
    }

    func scan() -> [DiscoveredModel] {
        (scanOllama() + scanHuggingFace()).sorted {
            if $0.runtime != $1.runtime { return $0.runtime.rawValue < $1.runtime.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func scanOllama() -> [DiscoveredModel] {
        let manifests = ollamaModelsURL.appendingPathComponent("manifests")
        guard let enumerator = fileManager.enumerator(at: manifests, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var models: [DiscoveredModel] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["schemaVersion"] != nil else { continue }
            let relative = url.path.replacingOccurrences(of: manifests.path + "/", with: "")
            let parts = relative.split(separator: "/").map(String.init)
            guard parts.count >= 4 else { continue }
            let namespace = parts[1]
            let model = parts.dropFirst(2).dropLast().joined(separator: "/")
            let tag = parts.last!
            let name = namespace == "library" ? "\(model):\(tag)" : "\(namespace)/\(model):\(tag)"
            let layers = object["layers"] as? [[String: Any]]
            let size = layers?.filter { ($0["mediaType"] as? String)?.contains("image.model") == true }
                .compactMap { ($0["size"] as? NSNumber)?.int64Value }.reduce(0, +)
            // Ollama writes a projector layer for vision models. `image.adapter`
            // is a LoRA and deliberately does not count.
            let supportsVision = layers?.contains { ($0["mediaType"] as? String) == "application/vnd.ollama.image.projector" } == true
            models.append(.init(runtime: .ollama, name: name, repository: nil, filename: nil, sizeBytes: size.flatMap { $0 > 0 ? $0 : nil }, roleHint: ModelCapability.role(inferringFrom: name), supportsVision: supportsVision))
        }
        return unique(models)
    }

    func scanHuggingFace() -> [DiscoveredModel] {
        guard let repositories = try? fileManager.contentsOfDirectory(at: huggingFaceHubURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var models: [DiscoveredModel] = []
        for repositoryURL in repositories where repositoryURL.lastPathComponent.hasPrefix("models--") {
            let encoded = String(repositoryURL.lastPathComponent.dropFirst("models--".count))
            let pieces = encoded.components(separatedBy: "--")
            guard pieces.count >= 2 else { continue }
            let repository = pieces[0] + "/" + pieces.dropFirst().joined(separator: "--")
            let snapshots = repositoryURL.appendingPathComponent("snapshots")
            guard let enumerator = fileManager.enumerator(at: snapshots, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            // Collected first, flagged second: directory enumeration order is not
            // guaranteed, so a projector must not depend on being visited last.
            var hasProjector = false
            var bases: [(label: String, filename: String, size: Int64?)] = []
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "gguf" {
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let filename = fileURL.lastPathComponent
                guard !filename.lowercased().contains("mmproj") else {
                    // The projector is not a standalone model, but its presence
                    // is what makes the base GGUF multimodal.
                    hasProjector = true
                    continue
                }
                let label = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                bases.append((label, filename, (attributes?[.size] as? NSNumber)?.int64Value))
            }
            models += bases.map {
                .init(runtime: .llamaCpp, name: $0.label, repository: repository, filename: $0.filename, sizeBytes: $0.size, roleHint: ModelCapability.role(inferringFrom: repository + " " + $0.filename), supportsVision: hasProjector)
            }
        }
        return unique(models)
    }

    private func unique(_ models: [DiscoveredModel]) -> [DiscoveredModel] {
        var seen: Set<String> = []
        return models.filter { seen.insert($0.id).inserted }
    }
}
