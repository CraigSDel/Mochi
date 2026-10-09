import Foundation

enum HardwareRecommendationFit: String, CaseIterable, Sendable {
    case safe = "Good fit"
    case caution = "Use caution"

    var rank: Int { self == .safe ? 0 : 1 }
}

struct HardwareModelRecommendation: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let modelID: String
    let source: String
    let role: RecommendationRole
    let runtime: ModelRuntime
    let fit: HardwareRecommendationFit
    let estimatedBytes: Int64
    let headroomBytes: Int64
    let reason: String
    let isInstalled: Bool
    let catalogRecommendation: ModelRecommendation?

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
    }

    var headroomText: String {
        ByteCountFormatter.string(fromByteCount: max(headroomBytes, 0), countStyle: .memory)
    }
}

struct HardwareRecommendationResult: Equatable, Sendable {
    let recommendations: [HardwareModelRecommendation]
    let message: String

    var isAvailable: Bool { !recommendations.isEmpty }

    func recommendations(for role: RecommendationRole) -> [HardwareModelRecommendation] {
        recommendations.filter { $0.role == role }
    }
}

struct HardwareRecommendationPolicy: Sendable {
    static let defaultContexts: [RecommendationRole: Int] = [
        .chat: 16_384,
        .coding: 8_192,
        .embedding: 8_192
    ]

    private let reserveBytes = ControllerPolicy.reserveBytes

    func evaluate(
        profile: HardwareProfile?,
        catalogRecommendations: [ModelRecommendation],
        installedModels: [DiscoveredModel]
    ) -> HardwareRecommendationResult {
        guard let profile, profile.physicalMemory > 0 else {
            return .init(recommendations: [], message: "Hardware memory is unavailable, so personalized model fit cannot be verified.")
        }
        let installed = installedModels.filter { $0.sizeBytes ?? 0 > 0 && !$0.supportsVision }
        let catalog = catalogRecommendations.filter {
            $0.compatibility == .compatible && ($0.sizeBytes ?? 0) > 0 && runtime(for: $0) != nil
        }
        let candidates = merge(catalog: catalog, installed: installed)
        let budget = profile.physicalMemory > reserveBytes ? profile.physicalMemory - reserveBytes : 0
        let evaluated = candidates.compactMap { candidate -> HardwareModelRecommendation? in
            let context = Self.defaultContexts[candidate.role] ?? 8_192
            let assessment = ControllerPolicy.memoryAssessment(
                modelBytes: [candidate.sizeBytes], contextSize: context, physicalMemory: profile.physicalMemory
            )
            guard assessment.severity != .high, let estimated = assessment.estimatedBytes else { return nil }
            let headroom = budget > estimated ? budget - estimated : 0
            let fit: HardwareRecommendationFit = assessment.severity == .safe ? .safe : .caution
            let headroomText = ByteCountFormatter.string(fromByteCount: Int64(clamping: headroom), countStyle: .memory)
            let reason = fit == .safe
                ? "Fits the conservative \(context / 1_024)K context with \(headroomText) of headroom."
                : "Fits, but leaves only \(headroomText) of conservative memory headroom."
            return .init(
                id: candidate.id, modelID: candidate.id, source: candidate.source,
                role: candidate.role, runtime: candidate.runtime, fit: fit,
                estimatedBytes: Int64(clamping: estimated), headroomBytes: Int64(clamping: headroom),
                reason: reason, isInstalled: candidate.isInstalled,
                catalogRecommendation: candidate.recommendation
            )
        }
        let sorted = evaluated.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            if $0.fit.rank != $1.fit.rank { return $0.fit.rank < $1.fit.rank }
            if $0.estimatedBytes != $1.estimatedBytes { return $0.estimatedBytes > $1.estimatedBytes }
            return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }
        let limited = RecommendationRole.allCases.flatMap { role in
            sorted.filter { $0.role == role }.prefix(3)
        }
        let message = limited.isEmpty
            ? "No verified model sizes fit this Mac’s conservative memory budget."
            : "Based on \(profile.physicalMemory / 1_073_741_824) GB unified memory and \(profile.chipText)."
        return .init(recommendations: limited, message: message)
    }

    func recommendations(
        profile: HardwareProfile?, catalogRecommendations: [ModelRecommendation], installedModels: [DiscoveredModel]
    ) -> [HardwareModelRecommendation] {
        evaluate(profile: profile, catalogRecommendations: catalogRecommendations, installedModels: installedModels).recommendations
    }

    private struct Candidate {
        let id: String
        let role: RecommendationRole
        let runtime: ModelRuntime
        let sizeBytes: Int64
        let source: String
        let isInstalled: Bool
        let recommendation: ModelRecommendation?
    }

    private func merge(catalog: [ModelRecommendation], installed: [DiscoveredModel]) -> [Candidate] {
        var result: [Candidate] = []
        var seen = Set<String>()
        for item in installed {
            let id = identity(item)
            guard seen.insert(id).inserted, let size = item.sizeBytes, size > 0 else { continue }
            let matching = catalog.first { identity($0) == id }
            result.append(.init(id: id, role: matching?.role ?? item.roleHint, runtime: item.runtime,
                                sizeBytes: size, source: matching?.source ?? "Installed", isInstalled: true,
                                recommendation: matching))
        }
        for item in catalog {
            let id = identity(item)
            guard seen.insert(id).inserted, let size = item.sizeBytes, size > 0,
                  let runtime = runtime(for: item) else { continue }
            result.append(.init(id: id, role: item.role, runtime: runtime, sizeBytes: size,
                                source: item.source, isInstalled: false, recommendation: item))
        }
        return result
    }

    private func identity(_ recommendation: ModelRecommendation) -> String {
        "llama:\(recommendation.repository ?? ""):\(recommendation.filename ?? recommendation.name)"
    }

    private func identity(_ model: DiscoveredModel) -> String {
        "llama:\(model.repository ?? ""):\(model.filename ?? model.name)"
    }

    private func runtime(for recommendation: ModelRecommendation) -> ModelRuntime? {
        if recommendation.runtime.localizedCaseInsensitiveContains("llama") { return .llamaCpp }
        return nil
    }
}
