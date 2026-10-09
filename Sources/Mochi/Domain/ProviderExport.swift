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
  static func records(
    configurations: [ServiceID: ServiceLaunchConfiguration],
    modelSettings: [ModelAssignmentKey: ModelSettingsProfile] = [:], hostname: String = "localhost"
  ) -> [String: ProviderExportRecord] {
    var result: [String: ProviderExportRecord] = [:]
    for id in ServiceID.allCases {
      guard let configuration = configurations[id] else { continue }
      let port = configuration.port
      if let llama = configuration.llama {
        let role = id == .autocomplete ? "fim" : (id == .embeddings ? "embedding" : "chat")
        let path =
          id == .autocomplete ? "/completion" : (id == .embeddings ? "/v1/embeddings" : "/v1")
        let recommendationRole: RecommendationRole =
          id == .autocomplete ? .coding : (id == .embeddings ? .embedding : .chat)
        let key = ModelAssignmentKey(
          runtime: .llamaCpp, modelID: "llama:\(llama.repository):\(llama.filename)", serviceID: id,
          role: recommendationRole)
        let defaultGeneration = ModelSettingsProfile.defaults(
          runtime: .llamaCpp, role: recommendationRole
        ).llama!.generation
        let profile = modelSettings[key]?.llama?.generation ?? defaultGeneration
        let generation: GenerationProfile? = id == .embeddings ? nil : profile
        result[id.rawValue] = .init(
          id: id.rawValue, label: llama.alias, modelName: llama.alias, provider: "llamacpp",
          type: role, apiHostname: hostname, apiPort: port, apiProtocol: "http", apiPath: path,
          apiKey: "", maxOutputTokens: generation?.maximumOutputTokens,
          temperature: generation?.temperature, topK: generation?.topK, topP: generation?.topP,
          repeatPenalty: generation?.repeatPenalty,
          autocompleteOutputLimit: generation?.autocompleteOutputLimit,
          fimTemplate: id == .autocomplete ? "automatic" : nil)
      }
    }
    return result
  }

  static func data(
    configurations: [ServiceID: ServiceLaunchConfiguration],
    modelSettings: [ModelAssignmentKey: ModelSettingsProfile] = [:], hostname: String = "localhost"
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(
      records(configurations: configurations, modelSettings: modelSettings, hostname: hostname))
  }
}
