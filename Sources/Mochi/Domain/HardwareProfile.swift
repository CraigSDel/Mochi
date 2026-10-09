import Foundation

enum HardwareArchitecture: String, Codable, Sendable {
  case appleSilicon
  case intel
  case unknown
}

struct HardwareProfile: Codable, Equatable, Sendable {
  let architecture: HardwareArchitecture
  let modelIdentifier: String?
  let chipName: String?
  let chipFamily: String?
  let chipGeneration: Int?
  let physicalMemory: UInt64
  let cpuCoreCount: Int?
  let performanceCoreCount: Int?
  let efficiencyCoreCount: Int?
  let gpuCoreCount: Int?
  let detectedAt: Date
  let unavailableFields: [String]

  var hasUsefulData: Bool { physicalMemory > 0 || chipName != nil || cpuCoreCount != nil }

  var memoryText: String {
    physicalMemory > 0
      ? ByteCountFormatter.string(
        fromByteCount: Int64(clamping: physicalMemory), countStyle: .memory)
      : "Unknown memory"
  }

  var chipText: String {
    chipName ?? chipFamily ?? (architecture == .intel ? "Intel Mac" : "Unknown chip")
  }

  var coreText: String {
    let cpu = cpuCoreCount.map { String($0) + " CPU cores" }
    let gpu = gpuCoreCount.map { String($0) + " GPU cores" }
    return [cpu, gpu].compactMap { $0 }.joined(separator: " · ")
  }

  static let unavailable = Self(
    architecture: .unknown,
    modelIdentifier: nil,
    chipName: nil,
    chipFamily: nil,
    chipGeneration: nil,
    physicalMemory: 0,
    cpuCoreCount: nil,
    performanceCoreCount: nil,
    efficiencyCoreCount: nil,
    gpuCoreCount: nil,
    detectedAt: Date(),
    unavailableFields: ["hardware profile"]
  )
}

struct HardwareModelSuggestion: Identifiable, Equatable, Sendable {
  let id: String
  let serviceID: ServiceID
  let currentModel: String
  let suggestedModel: String
  let reason: String
}

struct HardwareTuningPlan: Equatable, Sendable {
  let configurations: [ServiceID: ServiceLaunchConfiguration]
  let modelSuggestions: [HardwareModelSuggestion]
  let notes: [String]

  var hasConfigurationChanges: Bool { !configurations.isEmpty }
}
