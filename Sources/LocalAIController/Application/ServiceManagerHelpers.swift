import Foundation

extension ServiceManager {
    func modelRole(for serviceID: ServiceID) -> RecommendationRole {
        switch serviceID {
        case .autocomplete: .coding
        case .embeddings: .embedding
        case .llamaChat, .ollama: .chat
        }
    }

    func modelRuntime(for serviceID: ServiceID) -> ModelRuntime {
        configuration(for: serviceID).llama == nil ? .ollama : .llamaCpp
    }

    func modelID(for serviceID: ServiceID, role: RecommendationRole? = nil) -> String {
        let configuration = configuration(for: serviceID)
        if let llama = configuration.llama { return "llama:\(llama.repository):\(llama.filename)" }
        guard let ollama = configuration.ollama else { return "unknown" }
        switch role ?? modelRole(for: serviceID) {
        case .chat: return "ollama:\(ollama.chatModel)"
        case .coding: return "ollama:\(ollama.autocompleteModel)"
        case .embedding: return "ollama:\(ollama.embeddingModel)"
        }
    }

    func modelAssignmentKey(for serviceID: ServiceID, role: RecommendationRole? = nil) -> ModelAssignmentKey {
        let resolvedRole = role ?? modelRole(for: serviceID)
        return .init(runtime: modelRuntime(for: serviceID), modelID: modelID(for: serviceID, role: resolvedRole), serviceID: serviceID, role: resolvedRole)
    }

    func modelSettings(for serviceID: ServiceID) -> ModelSettingsProfile {
        let key = modelAssignmentKey(for: serviceID)
        return modelSettings[key] ?? .defaults(runtime: key.runtime, role: key.role)
    }

    func modelSettings(for serviceID: ServiceID, role: RecommendationRole) -> ModelSettingsProfile {
        let key = modelAssignmentKey(for: serviceID, role: role)
        return modelSettings[key] ?? .defaults(runtime: key.runtime, role: key.role)
    }

    func updateModelSettings(_ profile: ModelSettingsProfile, for serviceID: ServiceID, role: RecommendationRole? = nil) {
        guard !isConfigurationLocked(serviceID) else { return }
        let key = modelAssignmentKey(for: serviceID, role: role)
        var updated = modelSettings
        updated[key] = profile
        replaceModelSettings(updated)
        Task { await modelSettingsStore.save(updated) }
    }

    func refreshModelInventory() async { replaceInstalledModels(await modelManager.discover()) }
    func updateModelMetadata(_ metadata: [String: ModelMetadata]) {
        replaceModelMetadata(metadata)
        Task { await modelManager.saveMetadata(metadata) }
    }
    func downloadModel(_ recommendation: ModelRecommendation, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        try await modelManager.download(recommendation, progress: progress)
        await refreshModelInventory()
    }
    func deleteModel(_ model: DiscoveredModel) async throws {
        let assigned = modelMetadata[model.id]?.assignedServices ?? []
        let configured = ServiceID.allCases.filter { serviceUsesModel(model, in: $0) }
        guard !assigned.contains(where: isConfigurationLocked), configured.allSatisfy({ !isConfigurationLocked($0) }) else {
            throw ModelManagementError.activeAssignment
        }
        guard configured.isEmpty else { throw ModelManagementError.activeAssignment }
        try await modelManager.delete(model)
        var metadata = modelMetadata
        metadata.removeValue(forKey: model.id)
        updateModelMetadata(metadata)
        await refreshModelInventory()
    }
    func assignModel(_ model: DiscoveredModel, to serviceID: ServiceID, assigned: Bool) {
        guard !isConfigurationLocked(serviceID) else { return }
        var metadata = modelMetadata
        var entry = metadata[model.id] ?? ModelMetadata(alias: model.name, role: model.roleHint, assignedServices: [])
        if assigned {
            entry.assignedServices.insert(serviceID)
            var configuration = configuration(for: serviceID)
            if model.runtime == .llamaCpp, let repository = model.repository, let filename = model.filename {
                configuration.llama?.repository = repository
                configuration.llama?.filename = filename
                configuration.llama?.alias = entry.alias
            } else if model.runtime == .ollama, configuration.ollama != nil {
                switch serviceID {
                case .autocomplete: configuration.ollama?.autocompleteModel = model.name
                case .embeddings: configuration.ollama?.embeddingModel = model.name
                case .llamaChat: configuration.ollama?.chatModel = model.name
                case .ollama:
                    switch entry.role {
                    case .chat: configuration.ollama?.chatModel = model.name
                    case .coding: configuration.ollama?.autocompleteModel = model.name
                    case .embedding: configuration.ollama?.embeddingModel = model.name
                    }
                }
            }
            updateConfiguration(configuration, for: serviceID)
        } else {
            entry.assignedServices.remove(serviceID)
            var configuration = configuration(for: serviceID)
            let defaults = ServiceLaunchConfiguration.defaultValue(for: serviceID)
            if model.runtime == .llamaCpp,
               configuration.llama?.repository == model.repository,
               configuration.llama?.filename == model.filename {
                configuration.llama = defaults.llama
            } else if model.runtime == .ollama, var ollama = configuration.ollama {
                switch serviceID {
                case .autocomplete where OllamaModelReference.key(ollama.autocompleteModel) == OllamaModelReference.key(model.name):
                    ollama.autocompleteModel = defaults.ollama?.autocompleteModel ?? ollama.autocompleteModel
                case .embeddings where OllamaModelReference.key(ollama.embeddingModel) == OllamaModelReference.key(model.name):
                    ollama.embeddingModel = defaults.ollama?.embeddingModel ?? ollama.embeddingModel
                case .llamaChat, .ollama:
                    guard OllamaModelReference.key(ollama.chatModel) == OllamaModelReference.key(model.name) else { break }
                    ollama.chatModel = defaults.ollama?.chatModel ?? ollama.chatModel
                default: break
                }
                configuration.ollama = ollama
            }
            updateConfiguration(configuration, for: serviceID)
        }
        metadata[model.id] = entry
        updateModelMetadata(metadata)
        let settingsRole = model.runtime == .ollama ? entry.role : nil
        let settingsKey = modelAssignmentKey(for: serviceID, role: settingsRole)
        if modelSettings[settingsKey] == nil {
            var settings = modelSettings
            settings[settingsKey] = .defaults(runtime: settingsKey.runtime, role: settingsKey.role)
            replaceModelSettings(settings)
            Task { await modelSettingsStore.save(settings) }
        }
    }

    private func serviceUsesModel(_ model: DiscoveredModel, in serviceID: ServiceID) -> Bool {
        let configuration = configuration(for: serviceID)
        if model.runtime == .llamaCpp, let llama = configuration.llama {
            return llama.repository == model.repository && llama.filename == model.filename
        }
        guard model.runtime == .ollama, let ollama = configuration.ollama else { return false }
        return [ollama.chatModel, ollama.autocompleteModel, ollama.embeddingModel].contains {
            OllamaModelReference.key($0) == OllamaModelReference.key(model.name)
        }
    }

    func resolvedHosts(for bind: BindMode) async -> (display: String, health: String)? {
        switch bind {
        case .tailscale:
            guard await probe.commandPath("tailscale") != nil, let ip = await probe.tailscaleIP() else { return nil }
            return (ip, ip)
        case .localhost:
            return ("127.0.0.1", "127.0.0.1")
        case .lan:
            if let wifi = await probe.wifiIP() { return (wifi, "127.0.0.1") }
            guard let ip = await probe.localNetworkIP() else { return nil }
            return (ip, "127.0.0.1")
        }
    }

    func serviceName(_ id: ServiceID) -> String {
        definitions.first(where: { $0.id == id })?.name ?? id.rawValue
    }

    func definition(for id: ServiceID) -> ServiceDefinition? {
        definitions.first { $0.id == id }
    }

    func llamaModelSize(_ llama: LlamaLaunchConfiguration, serviceID: ServiceID) -> Int64? {
        if let size = installedModels.first(where: {
            $0.runtime == .llamaCpp && $0.repository == llama.repository && $0.filename == llama.filename
        })?.sizeBytes { return size }
        if let size = recommendationMetadata.first(where: {
            $0.repository == llama.repository && $0.filename == llama.filename
        })?.sizeBytes { return size }
        let defaults = ServiceLaunchConfiguration.defaultValue(for: serviceID).llama
        return defaults?.repository == llama.repository && defaults?.filename == llama.filename
            ? definition(for: serviceID)?.estimatedBytes
            : nil
    }
}

extension ServiceManager: ModelDownloadExecuting {}
