import Foundation

struct ProviderExportRecord: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let modelName: String
    let provider: String
    let type: String
    let apiHostname: String
    let apiPort: Int
    let apiProtocol: String
    let apiPath: String
    let apiKey: String
    let maxOutputTokens: Int?
    let temperature: Double?
    let topK: Int?
    let topP: Double?
    let repeatPenalty: Double?
    let autocompleteOutputLimit: Int?
    let fimTemplate: String?
}

enum ProviderExportBuilder {
    static func records(configurations: [ServiceID: ServiceLaunchConfiguration], modelSettings: [ModelAssignmentKey: ModelSettingsProfile] = [:], hostname: String = "localhost") -> [String: ProviderExportRecord] {
        var result: [String: ProviderExportRecord] = [:]
        for id in [ServiceID.llamaChat, .autocomplete, .embeddings, .ollama] {
            guard let configuration = configurations[id] else { continue }
            let port = configuration.port
            if let llama = configuration.llama {
                let role = id == .autocomplete ? "fim" : (id == .embeddings ? "embedding" : "chat")
                let path = id == .autocomplete ? "/completion" : (id == .embeddings ? "/v1/embeddings" : "/v1")
                let recommendationRole: RecommendationRole = id == .autocomplete ? .coding : (id == .embeddings ? .embedding : .chat)
                let key = ModelAssignmentKey(runtime: .llamaCpp, modelID: "llama:\(llama.repository):\(llama.filename)", serviceID: id, role: recommendationRole)
                let defaultGeneration = ModelSettingsProfile.defaults(runtime: .llamaCpp, role: recommendationRole).llama!.generation
                let profile = modelSettings[key]?.llama?.generation ?? defaultGeneration
                let generation: GenerationProfile? = id == .embeddings ? nil : profile
                result[id.rawValue] = .init(id: id.rawValue, label: llama.alias, modelName: llama.alias, provider: "llamacpp", type: role, apiHostname: hostname, apiPort: port, apiProtocol: "http", apiPath: path, apiKey: "", maxOutputTokens: generation?.maximumOutputTokens, temperature: generation?.temperature, topK: generation?.topK, topP: generation?.topP, repeatPenalty: generation?.repeatPenalty, autocompleteOutputLimit: generation?.autocompleteOutputLimit, fimTemplate: id == .autocomplete ? "automatic" : nil)
            } else if let ollama = configuration.ollama {
                let chatKey = ModelAssignmentKey(runtime: .ollama, modelID: "ollama:\(ollama.chatModel)", serviceID: id, role: .chat)
                let autocompleteKey = ModelAssignmentKey(runtime: .ollama, modelID: "ollama:\(ollama.autocompleteModel)", serviceID: id, role: .coding)
                let chat = modelSettings[chatKey]?.ollama?.generation ?? ModelSettingsProfile.defaults(runtime: .ollama, role: .chat).ollama!.generation
                result["ollama-chat"] = .init(id: "ollama-chat", label: "Ollama Chat", modelName: ollama.chatModel, provider: "ollama", type: "chat", apiHostname: hostname, apiPort: port, apiProtocol: "http", apiPath: "/v1", apiKey: "", maxOutputTokens: chat.maximumOutputTokens, temperature: chat.temperature, topK: chat.topK, topP: chat.topP, repeatPenalty: chat.repeatPenalty, autocompleteOutputLimit: chat.autocompleteOutputLimit, fimTemplate: nil)
                let autocomplete = modelSettings[autocompleteKey]?.ollama?.generation ?? ModelSettingsProfile.defaults(runtime: .ollama, role: .coding).ollama!.generation
                result["ollama-autocomplete"] = .init(id: "ollama-autocomplete", label: "Ollama Autocomplete", modelName: ollama.autocompleteModel, provider: "ollama", type: "fim", apiHostname: hostname, apiPort: port, apiProtocol: "http", apiPath: "/v1", apiKey: "", maxOutputTokens: autocomplete.maximumOutputTokens, temperature: autocomplete.temperature, topK: autocomplete.topK, topP: autocomplete.topP, repeatPenalty: autocomplete.repeatPenalty, autocompleteOutputLimit: autocomplete.autocompleteOutputLimit, fimTemplate: "automatic")
                result["ollama-embedding"] = .init(id: "ollama-embedding", label: "Ollama Embeddings", modelName: ollama.embeddingModel, provider: "ollama", type: "embedding", apiHostname: hostname, apiPort: port, apiProtocol: "http", apiPath: "/v1/embeddings", apiKey: "", maxOutputTokens: nil, temperature: nil, topK: nil, topP: nil, repeatPenalty: nil, autocompleteOutputLimit: nil, fimTemplate: nil)
            }
        }
        return result
    }

    static func data(configurations: [ServiceID: ServiceLaunchConfiguration], modelSettings: [ModelAssignmentKey: ModelSettingsProfile] = [:], hostname: String = "localhost") throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records(configurations: configurations, modelSettings: modelSettings, hostname: hostname))
    }
}
