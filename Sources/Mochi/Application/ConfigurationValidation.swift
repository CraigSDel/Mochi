import Foundation

extension ServiceManager {
  func validationIssues(for id: ServiceID) -> [ConfigurationIssue] {
    let config = configuration(for: id)
    var issues: [ConfigurationIssue] = []
    if !ControllerPolicy.validPort(config.port) {
      issues.append(.init(field: "port", message: "Port must be between 1024 and 65535."))
    }
    if let llama = config.llama {
      for (field, value, label) in [
        ("repository", llama.repository, "Repository"),
        ("filename", llama.filename, "GGUF filename"), ("alias", llama.alias, "Model alias"),
      ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(field: field, message: "\(label) is required."))
      }
      if llama.contextSize <= 0 {
        issues.append(
          .init(field: "contextSize", message: "Context size must be greater than zero."))
      }
      if !(0...999).contains(llama.gpuLayers) {
        issues.append(.init(field: "gpuLayers", message: "GPU layers must be between 0 and 999."))
      }
      if !Self.validCache(llama.kvCacheKeyType) {
        issues.append(.init(field: "kvCacheKeyType", message: "KV key cache type is invalid."))
      }
      if !Self.validCache(llama.kvCacheValueType) {
        issues.append(.init(field: "kvCacheValueType", message: "KV value cache type is invalid."))
      }
      if !(0...4096).contains(llama.cacheReuse) {
        issues.append(
          .init(field: "cacheReuse", message: "Cache reuse must be between 0 and 4096."))
      }
      if !(1...4096).contains(llama.batchSize) {
        issues.append(.init(field: "batchSize", message: "Batch size must be between 1 and 4096."))
      }
      if !(1...4096).contains(llama.ubatchSize) {
        issues.append(
          .init(field: "ubatchSize", message: "Micro-batch size must be between 1 and 4096."))
      }
      if !(0...256).contains(llama.threads) {
        issues.append(.init(field: "threads", message: "Threads must be between 0 and 256."))
      }
      if !(0...256).contains(llama.threadsBatch) {
        issues.append(
          .init(field: "threadsBatch", message: "Batch threads must be between 0 and 256."))
      }
      issues += generationIssues(llama.generation, fieldPrefix: "generation")
    } else {
      issues.append(.init(field: "runtime", message: "Runtime configuration is missing."))
    }
    return issues
  }

  private static func validCache(_ value: String) -> Bool {
    ["q4_0", "q4_1", "q8_0", "f16", "f32"].contains(value)
  }

  private func generationIssues(_ profile: GenerationProfile, fieldPrefix: String)
    -> [ConfigurationIssue]
  {
    var issues: [ConfigurationIssue] = []
    if !(1...32_768).contains(profile.maximumOutputTokens) {
      issues.append(
        .init(
          field: "\(fieldPrefix).maximumOutputTokens",
          message: "Maximum output tokens must be between 1 and 32,768."))
    }
    if !(0...2).contains(profile.temperature) {
      issues.append(
        .init(field: "\(fieldPrefix).temperature", message: "Temperature must be between 0 and 2."))
    }
    if !(0...200).contains(profile.topK) {
      issues.append(
        .init(field: "\(fieldPrefix).topK", message: "Top-k must be between 0 and 200."))
    }
    if !(0...1).contains(profile.topP) || profile.topP == 0 {
      issues.append(
        .init(field: "\(fieldPrefix).topP", message: "Top-p must be greater than 0 and at most 1."))
    }
    if !(0.5...2).contains(profile.repeatPenalty) {
      issues.append(
        .init(
          field: "\(fieldPrefix).repeatPenalty",
          message: "Repeat penalty must be between 0.5 and 2."))
    }
    if !(1...8_192).contains(profile.autocompleteOutputLimit) {
      issues.append(
        .init(
          field: "\(fieldPrefix).autocompleteOutputLimit",
          message: "Autocomplete output limit must be between 1 and 8,192."))
    }
    return issues
  }
}
