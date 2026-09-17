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

    var id: String {
        switch runtime {
        case .llamaCpp: "llama:\(repository ?? ""):\(filename ?? name)"
        case .ollama: "ollama:\(name)"
        }
    }

    static func inferredRole(from value: String) -> RecommendationRole {
        let lower = value.lowercased()
        if lower.contains("embed") || lower.contains("bert") { return .embedding }
        if lower.contains("coder") || lower.contains("code") || lower.contains("fim") { return .coding }
        return .chat
    }
}

enum ModelAvailability: String, Sendable {
    case installed = "Installed"
    case catalog = "Download required"
    case custom = "Custom"
    case missing = "Unavailable"
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
            models.append(.init(runtime: .ollama, name: name, repository: nil, filename: nil, sizeBytes: size.flatMap { $0 > 0 ? $0 : nil }, roleHint: DiscoveredModel.inferredRole(from: name)))
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
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "gguf" {
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let filename = fileURL.lastPathComponent
                guard !filename.lowercased().contains("mmproj") else { continue }
                let label = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                let size = (attributes?[.size] as? NSNumber)?.int64Value
                models.append(.init(runtime: .llamaCpp, name: label, repository: repository, filename: filename, sizeBytes: size, roleHint: DiscoveredModel.inferredRole(from: repository + " " + filename)))
            }
        }
        return unique(models)
    }

    private func unique(_ models: [DiscoveredModel]) -> [DiscoveredModel] {
        var seen: Set<String> = []
        return models.filter { seen.insert($0.id).inserted }
    }
}

enum ModelOptionBuilder {
    static func options(
        runtime: ModelRuntime,
        role: RecommendationRole,
        installed: [DiscoveredModel],
        recommendations: [ModelRecommendation],
        currentLlama: LlamaLaunchConfiguration? = nil,
        currentOllamaName: String? = nil
    ) -> [ModelOption] {
        var result = installed.filter { $0.runtime == runtime }.map {
            ModelOption(id: $0.id, runtime: $0.runtime, name: $0.name, repository: $0.repository, filename: $0.filename, sizeBytes: $0.sizeBytes, roleHint: $0.roleHint, availability: .installed)
        }
        let installedKeys = Set(result.map(selectionKey))
        let catalog: [ModelOption] = recommendations.compactMap { recommendation in
            guard recommendation.compatibility != .incompatible else { return nil }
            switch runtime {
            case .llamaCpp:
                guard let repository = recommendation.repository, let filename = recommendation.filename else { return nil }
                let option = ModelOption(id: "catalog:llama:\(repository):\(filename)", runtime: .llamaCpp, name: recommendation.name, repository: repository, filename: filename, sizeBytes: recommendation.sizeBytes, roleHint: recommendation.role, availability: .catalog)
                return installedKeys.contains(selectionKey(option)) ? nil : option
            case .ollama:
                guard let name = recommendation.modelName else { return nil }
                let option = ModelOption(id: "catalog:ollama:\(name)", runtime: .ollama, name: name, repository: nil, filename: nil, sizeBytes: recommendation.sizeBytes, roleHint: recommendation.role, availability: .catalog)
                return installedKeys.contains(selectionKey(option)) ? nil : option
            }
        }
        result += catalog
        result.sort {
            let lhs = rank($0, role: role), rhs = rank($1, role: role)
            return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
        }

        let current: ModelOption?
        switch runtime {
        case .llamaCpp:
            current = currentLlama.map { .init(id: "current:llama:\($0.repository):\($0.filename)", runtime: .llamaCpp, name: $0.alias, repository: $0.repository, filename: $0.filename, sizeBytes: nil, roleHint: role, availability: .missing) }
        case .ollama:
            current = currentOllamaName.map { .init(id: "current:ollama:\($0)", runtime: .ollama, name: $0, repository: nil, filename: nil, sizeBytes: nil, roleHint: role, availability: .missing) }
        }
        if let current, !result.contains(where: { selectionKey($0) == selectionKey(current) }) { result.append(current) }
        return result
    }

    static func selectionKey(_ option: ModelOption) -> String {
        switch option.runtime {
        case .llamaCpp: "\(option.repository ?? "")|\(option.filename ?? "")"
        case .ollama: option.name
        }
    }

    private static func rank(_ option: ModelOption, role: RecommendationRole) -> Int {
        let availability = option.availability == .installed ? 0 : 2
        return availability + (option.roleHint == role ? 0 : 1)
    }
}