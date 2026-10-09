import Foundation

enum HardwareTuningPolicy {
    static func plan(
        profile: HardwareProfile,
        configurations: [ServiceID: ServiceLaunchConfiguration],
        installedModels: [DiscoveredModel],
        recommendations: [ModelRecommendation]
    ) -> HardwareTuningPlan {
        guard profile.physicalMemory > 0 else {
            return .init(configurations: [:], modelSuggestions: [], notes: ["Hardware memory could not be detected; no settings were changed."])
        }
        let tier = memoryTier(profile.physicalMemory)
        let preset: PerformancePreset = tier <= 16 ? .fast : .balanced
        var tuned: [ServiceID: ServiceLaunchConfiguration] = [:]
        var suggestions: [HardwareModelSuggestion] = []

        for (serviceID, configuration) in configurations {
            var updated = configuration
            if var llama = updated.llama {
                llama = PerformancePresetMapper.llama(llama, preset: preset)
                llama.contextSize = safeContext(for: serviceID, tier: tier, requested: llama.contextSize)
                llama.batchSize = min(llama.batchSize, batchSize(for: tier))
                llama.ubatchSize = min(llama.ubatchSize, max(64, batchSize(for: tier) / 2))
                updated.llama = llama
                if let suggestion = llamaSuggestion(serviceID: serviceID, configuration: llama, tier: tier, installedModels: installedModels, recommendations: recommendations) {
                    suggestions.append(suggestion)
                }
            }
            if updated != configuration { tuned[serviceID] = updated }
        }

        var notes = ["Safe tuning uses " + memoryLabel(tier) + " of physical memory and keeps selected models unchanged."]
        if let chip = profile.chipName { notes.append("Detected " + chip + ".") }
        if !profile.unavailableFields.isEmpty {
            notes.append("Some hardware fields were unavailable; memory-based limits remain conservative.")
        }
        return .init(configurations: tuned, modelSuggestions: suggestions, notes: notes)
    }

    private static func memoryTier(_ bytes: UInt64) -> Int {
        let gib = Double(bytes) / 1_073_741_824
        if gib <= 8 { return 8 }
        if gib <= 16 { return 16 }
        if gib < 64 { return 32 }
        return 64
    }

    private static func safeContext(for serviceID: ServiceID, tier: Int, requested: Int) -> Int {
        let limit: Int
        switch tier {
        case 8: limit = 4_096
        case 16: limit = 8_192
        case 32: limit = serviceID == .llamaChat ? 16_384 : 8_192
        default: limit = serviceID == .llamaChat ? 32_768 : 16_384
        }
        return ContextSizeOptions.normalized(min(max(requested, 4_096), limit))
    }

    private static func batchSize(for tier: Int) -> Int { tier <= 8 ? 128 : tier <= 16 ? 256 : 512 }
    private static func memoryLabel(_ tier: Int) -> String { tier == 64 ? "64 GB or more" : "up to " + String(tier) + " GB" }

    private static func llamaSuggestion(
        serviceID: ServiceID,
        configuration: LlamaLaunchConfiguration,
        tier: Int,
        installedModels: [DiscoveredModel],
        recommendations: [ModelRecommendation]
    ) -> HardwareModelSuggestion? {
        let currentSize = installedModels.first { $0.runtime == .llamaCpp && $0.repository == configuration.repository && $0.filename == configuration.filename }?.sizeBytes
            ?? recommendations.first { $0.repository == configuration.repository && $0.filename == configuration.filename }?.sizeBytes
        guard let currentSize else { return nil }
        let assessment = ControllerPolicy.memoryAssessment(modelBytes: [currentSize], contextSize: safeContext(for: serviceID, tier: tier, requested: configuration.contextSize), physicalMemory: UInt64(tier) * 1_073_741_824)
        guard assessment.severity == .high else { return nil }
        guard let candidate = recommendations.filter({ $0.role == role(for: serviceID) && $0.runtime.lowercased().contains("llama") && ($0.sizeBytes ?? Int64.max) < currentSize && $0.compatibility != .incompatible }).min(by: { ($0.sizeBytes ?? Int64.max) < ($1.sizeBytes ?? Int64.max) }) else { return nil }
        return .init(id: serviceID.rawValue + ":" + candidate.id, serviceID: serviceID, currentModel: configuration.alias, suggestedModel: candidate.name, reason: "The selected model exceeds the conservative memory budget for this Mac.")
    }

    private static func role(for serviceID: ServiceID) -> RecommendationRole {
        switch serviceID { case .autocomplete: .coding; case .embeddings: .embedding; case .llamaChat: .chat }
    }
}
