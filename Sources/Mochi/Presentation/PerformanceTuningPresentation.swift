import SwiftUI

enum BeginnerPerformanceProfile: String, CaseIterable, Identifiable {
    case fast, balanced, quality, custom
    static var allCases: [Self] { [.fast, .balanced, .quality] }
    var id: String { rawValue }
    var preset: PerformancePreset { PerformancePreset(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .quality: "Better answers"
        case .custom: "Custom"
        case .fast: "Fast"
        case .balanced: "Balanced"
        }
    }
    var cardTitle: String { self == .fast ? "Faster" : title }
    var summary: String {
        switch self {
        case .fast: "Uses less memory and responds sooner."
        case .balanced: "Recommended for most people."
        case .quality: "Supports longer conversations and responses, but uses more memory."
        case .custom: "Your own combination of settings."
        }
    }
}

struct MemoryStatusPresentation: Equatable {
    let message: String
    let symbol: String
    let color: Color
}

enum PerformanceTuningPresentation {
    static let responseOptions = [256, 1_024, 2_048]
    static let responseLabels = ["Short", "Standard", "Long"]

    static func activeProfile(for settings: LlamaModelSettings?, role: RecommendationRole, baselineContext: Int?) -> BeginnerPerformanceProfile {
        guard let settings else { return .balanced }
        for profile in BeginnerPerformanceProfile.allCases {
            let mapped = PerformancePresetMapper.llama(settings, preset: profile.preset, baselineContext: baselineContext)
            if mapped == settings { return profile }
        }
        return .custom
    }

    static func responseValue(for generation: GenerationProfile?, role: RecommendationRole) -> Int {
        guard let generation else { return responseOptions[1] }
        return role == .coding ? generation.autocompleteOutputLimit : generation.maximumOutputTokens
    }

    static func responseLabel(for generation: GenerationProfile?, role: RecommendationRole) -> String {
        let value = responseValue(for: generation, role: role)
        guard let index = responseOptions.firstIndex(of: value) else { return "Custom (\(value) tokens)" }
        return "\(responseLabels[index]) (\(value) tokens)"
    }

    static func setResponseValue(_ value: Int, on generation: inout GenerationProfile, role: RecommendationRole) {
        generation.maximumOutputTokens = value
        if role == .coding { generation.autocompleteOutputLimit = value }
    }

    static func memoryStatus(for severity: MemoryRiskSeverity) -> MemoryStatusPresentation {
        switch severity {
        case .safe: .init(message: "Good to go", symbol: "checkmark.circle.fill", color: .green)
        case .caution: .init(message: "May use more memory", symbol: "exclamationmark.triangle.fill", color: .orange)
        case .high: .init(message: "Consider a smaller context or model", symbol: "exclamationmark.octagon.fill", color: .red)
        case .unverified: .init(message: "Memory use is unverified", symbol: "questionmark.circle.fill", color: .secondary)
        }
    }
}
