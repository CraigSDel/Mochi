import Foundation

enum PerformanceGuidanceSeverity: String, Equatable, Sendable {
  case safe, caution, high, unverified
}

struct PerformanceGuidance: Identifiable, Equatable, Sendable {
  let id: String
  let runtime: ModelRuntime
  let modelLabel: String
  let severity: PerformanceGuidanceSeverity
  let summary: String
  let recommendations: [String]

  var isInformational: Bool { recommendations.contains { $0.hasPrefix("MLX/") } }

  static func make(
    runtime: ModelRuntime,
    modelLabel: String,
    modelBytes: [Int64]?,
    quantization: String?,
    contextSize: Int,
    parallelRequests: Int = 1,
    loadedModelCount: Int = 1,
    kvCacheType: String? = nil,
    cacheReuse: Int = 256,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> Self {
    let assessment = ControllerPolicy.memoryAssessment(
      modelBytes: modelBytes,
      contextSize: contextSize,
      parallelRequests: parallelRequests,
      loadedModelCount: loadedModelCount,
      cacheReuse: cacheReuse,
      physicalMemory: physicalMemory
    )
    var recommendations = [assessment.message]
    let largestModelBytes = modelBytes?.max()
    let largeModel = largestModelBytes.map { $0 >= 12 * 1_073_741_824 } == true
    let quantizationText = quantization?.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowerQuantization = quantizationText?.lowercased() ?? ""

    if largeModel && !lowerQuantization.contains("q4") && !lowerQuantization.contains("q3") {
      recommendations.append(
        "For a large model, prefer a 4-bit or 3-bit quantization when an equivalent option is available."
      )
    } else if largeModel {
      recommendations.append(
        "This large model is using a low-bit quantization; keeping system memory headroom is still important during long contexts."
      )
    }

    switch assessment.severity {
    case .caution:
      recommendations.append(
        "Reduce context length or concurrent requests if generation becomes slow or macOS reports memory pressure."
      )
    case .high:
      recommendations.append(
        "Reduce context length and choose a smaller model before starting; swapping can make generation dramatically slower."
      )
    case .safe, .unverified:
      break
    }

    recommendations.append(
      "llama.cpp context length is the main memory control exposed by this controller; lower it before increasing model size."
    )
    if cacheReuse > 256 {
      recommendations.append(
        "llama.cpp cache reuse is set aggressively; it can improve repeated prompts but may increase memory pressure."
      )
    }

    recommendations.append(
      "For higher throughput, consider a smaller or mixture-of-experts model; dense models read all model weights for each generated token."
    )
    recommendations.append(
      "MLX/oMLX may use Apple Silicon unified memory efficiently, but this controller does not install, launch, or manage those runtimes."
    )

    return .init(
      id: "\(runtime.rawValue):\(modelLabel)",
      runtime: runtime,
      modelLabel: modelLabel,
      severity: mapSeverity(assessment.severity),
      summary: summary(for: assessment, runtime: runtime),
      recommendations: recommendations
    )
  }

  private static func mapSeverity(_ severity: MemoryRiskSeverity) -> PerformanceGuidanceSeverity {
    switch severity {
    case .safe: .safe
    case .caution: .caution
    case .high: .high
    case .unverified: .unverified
    }
  }

  private static func summary(for assessment: MemoryAssessment, runtime: ModelRuntime) -> String {
    let runtimeName = "llama.cpp"
    switch assessment.severity {
    case .safe: return "\(runtimeName) has usable memory headroom for the configured model."
    case .caution: return "\(runtimeName) is close to the conservative memory budget."
    case .high:
      return "\(runtimeName) may run under severe memory pressure with this configuration."
    case .unverified: return "Model memory use is unverified because size metadata is unavailable."
    }
  }
}

enum PerformanceGuidanceBuilder {
  static func make(
    configurations: [ServiceID: ServiceLaunchConfiguration],
    installedModels: [DiscoveredModel],
    recommendations: [ModelRecommendation],
    physicalMemory: UInt64,
    defaultLlamaConfiguration: LlamaLaunchConfiguration?,
    defaultLlamaSize: Int64?
  ) -> [PerformanceGuidance] {
    let llama = configurations[.llamaChat]?.llama.flatMap { configuration in
      PerformanceGuidance.make(
        runtime: .llamaCpp,
        modelLabel: configuration.alias,
        modelBytes: [
          llamaSize(
            configuration,
            installedModels: installedModels,
            recommendations: recommendations,
            defaultConfiguration: defaultLlamaConfiguration,
            defaultSize: defaultLlamaSize
          )
        ].compactMap { $0 },
        quantization: configuration.filename,
        contextSize: configuration.contextSize,
        cacheReuse: configuration.cacheReuse,
        physicalMemory: physicalMemory
      )
    }
    return [llama].compactMap { $0 }
  }

  private static func llamaSize(
    _ configuration: LlamaLaunchConfiguration,
    installedModels: [DiscoveredModel],
    recommendations: [ModelRecommendation],
    defaultConfiguration: LlamaLaunchConfiguration?,
    defaultSize: Int64?
  ) -> Int64? {
    installedModels.first {
      $0.runtime == .llamaCpp && $0.repository == configuration.repository
        && $0.filename == configuration.filename
    }?.sizeBytes
      ?? recommendations.first {
        $0.repository == configuration.repository && $0.filename == configuration.filename
      }?.sizeBytes
      ?? (defaultConfiguration?.repository == configuration.repository
        && defaultConfiguration?.filename == configuration.filename ? defaultSize : nil)
  }

}
