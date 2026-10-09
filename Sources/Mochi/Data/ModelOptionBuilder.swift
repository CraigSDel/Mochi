import Foundation

enum ModelOptionBuilder {
    static func options(
        runtime: ModelRuntime,
        role: RecommendationRole,
        installed: [DiscoveredModel],
        recommendations: [ModelRecommendation],
        currentLlama: LlamaLaunchConfiguration? = nil,
        includeCatalog: Bool = true
    ) -> [ModelOption] {
        let runtimeInstalled = installed.filter { $0.runtime == runtime }
        var result = runtimeInstalled
            .filter { !$0.supportsVision }
            .map { model in
                ModelOption(
                    id: model.id, runtime: model.runtime, name: model.name, repository: model.repository,
                    filename: model.filename, sizeBytes: model.sizeBytes, roleHint: model.roleHint,
                    availability: .installed
                )
            }
        let installedKeys = Set(result.map(selectionKey))
        let catalog: [ModelOption] = includeCatalog ? recommendations.compactMap { recommendation in
            guard recommendation.compatibility != .incompatible else { return nil }
            guard let repository = recommendation.repository, let filename = recommendation.filename else { return nil }
            let option = ModelOption(id: "catalog:llama:\(repository):\(filename)", runtime: .llamaCpp, name: recommendation.name, repository: repository, filename: filename, sizeBytes: recommendation.sizeBytes, roleHint: recommendation.role, availability: .catalog)
            return installedKeys.contains(selectionKey(option)) ? nil : option
        } : []
        result += catalog
        result.sort {
            let lhs = rank($0, role: role), rhs = rank($1, role: role)
            return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
        }
        if let current = currentOption(runtime: runtime, installed: runtimeInstalled, role: role, currentLlama: currentLlama),
           !result.contains(where: { selectionKey($0) == selectionKey(current) }) {
            result.append(current)
        }
        return result
    }

    /// The saved configuration is always represented, even when it resolves to
    /// nothing installed. A vision model that is already assigned therefore
    /// surfaces as `.unsupported` rather than disappearing from the picker.
    private static func currentOption(runtime: ModelRuntime, installed: [DiscoveredModel], role: RecommendationRole, currentLlama: LlamaLaunchConfiguration?) -> ModelOption? {
        guard let llama = currentLlama else { return nil }
        let vision = installed.contains { $0.repository == llama.repository && $0.filename == llama.filename && $0.supportsVision }
        return .init(id: "current:llama:\(llama.repository):\(llama.filename)", runtime: .llamaCpp, name: llama.alias, repository: llama.repository, filename: llama.filename, sizeBytes: nil, roleHint: role, availability: vision ? .unsupported : .missing)
    }

    static func selectionKey(_ option: ModelOption) -> String {
        "\(option.repository ?? "")|\(option.filename ?? "")"
    }

    static func recommendation(for option: ModelOption, from recommendations: [ModelRecommendation]) -> ModelRecommendation? {
        recommendations.first { recommendation in
            recommendation.repository == option.repository && recommendation.filename == option.filename
        }
    }

    private static func rank(_ option: ModelOption, role: RecommendationRole) -> Int {
        let availability = option.availability == .installed ? 0 : 2
        return availability + (option.roleHint == role ? 0 : 1)
    }
}
