import Foundation

enum ControllerPolicy {
  static let reserveBytes: UInt64 = 14 * 1_073_741_824
  static let maxModelBytes: UInt64 = 20 * 1_073_741_824
  static let kvCacheBytesPerToken: UInt64 = 48 * 1_024
  static let supportedArchitectures = [
    "llama", "qwen2", "qwen3", "mistral", "gemma", "phi3", "bert", "nomic-bert", "gpt-oss",
  ]
  static func validPort(_ port: Int) -> Bool { (1024...65535).contains(port) }
  static func fits(
    sizeBytes: Int64?, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> Bool {
    guard let sizeBytes, sizeBytes > 0 else { return false }
    let available = physicalMemory > reserveBytes ? physicalMemory - reserveBytes : 0
    return UInt64(sizeBytes) <= min(maxModelBytes, available)
  }
  static func compatibility(
    sizeBytes: Int64?, architectureKnown: Bool, gated: Bool, multimodal: Bool, cloudOnly: Bool,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> Compatibility {
    if gated || multimodal || cloudOnly { return .incompatible }
    guard architectureKnown, sizeBytes != nil else { return .unverified }
    return fits(sizeBytes: sizeBytes, physicalMemory: physicalMemory) ? .compatible : .incompatible
  }
  static func memoryAssessment(
    modelBytes: [Int64]?, contextSize: Int, parallelRequests: Int = 1, loadedModelCount: Int = 1,
    cacheReuse: Int = 256, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> MemoryAssessment {
    let budget = physicalMemory > reserveBytes ? physicalMemory - reserveBytes : 0
    guard let modelBytes, !modelBytes.isEmpty, modelBytes.allSatisfy({ $0 > 0 }) else {
      return .init(
        severity: .unverified, estimatedBytes: nil, usableBudgetBytes: budget,
        message: "Memory use is unverified because model-size metadata is unavailable.")
    }
    let weights = modelBytes.reduce(UInt64(0)) { $0 + UInt64($1) }
    let contexts = UInt64(max(contextSize, 0))
    let requests = UInt64(max(parallelRequests, 1))
    let loaded = UInt64(max(loadedModelCount, 1))
    let multiplier = UInt64(max(cacheReuse, 0) > 256 ? 2 : 1)
    let kvCache = contexts.multipliedReportingOverflow(by: kvCacheBytesPerToken).partialValue
      .multipliedReportingOverflow(by: requests).partialValue.multipliedReportingOverflow(
        by: loaded
      ).partialValue.multipliedReportingOverflow(by: multiplier).partialValue
    let estimated = weights.addingReportingOverflow(kvCache).partialValue
    let severity: MemoryRiskSeverity =
      budget == 0 || estimated > budget
      ? .high : (Double(estimated) / Double(budget) >= 0.8 ? .caution : .safe)
    let estimateText = ByteCountFormatter.string(
      fromByteCount: Int64(clamping: estimated), countStyle: .memory)
    let budgetText = ByteCountFormatter.string(
      fromByteCount: Int64(clamping: budget), countStyle: .memory)
    let message: String
    switch severity {
    case .safe:
      message =
        "Estimated memory: \(estimateText) of \(budgetText), with \(ByteCountFormatter.string(fromByteCount: Int64(clamping: budget - estimated), countStyle: .memory)) of headroom."
    case .caution:
      message =
        "Estimated memory: \(estimateText) of \(budgetText). Performance may degrade under memory pressure."
    case .high:
      message =
        "Estimated memory: \(estimateText), above the \(budgetText) safe budget. The Mac may swap heavily or the service may fail."
    case .unverified: message = "Memory use is unverified."
    }
    return .init(
      severity: severity, estimatedBytes: estimated, usableBudgetBytes: budget, message: message)
  }
}
