import Foundation

struct OllamaLibraryProvider: RecommendationProvider {
    let sourceName = "Ollama Library"
    private let fetcher: any HTTPFetching

    init(fetcher: any HTTPFetching = URLSessionFetching()) { self.fetcher = fetcher }

    func fetch() async throws -> [ModelRecommendation] {
        let response = try await fetcher.fetch(Self.listingURL, timeout: Self.requestTimeout)
        guard response.isSuccess, let html = String(data: response.data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return OllamaLibraryParser.entries(html: html).map(recommendation(for:))
    }

    private func recommendation(for entry: OllamaLibraryEntry) -> ModelRecommendation {
        let multimodal = ModelCapability.isMultimodal(badges: entry.badges)
        let cloudOnly = ModelCapability.isCloudOnly(badges: entry.badges)
        // An explicit `embedding` badge outranks a name substring: "nomic-embed-text"
        // is an embedding model even though the badge is the authoritative signal.
        let role: RecommendationRole = entry.badges.contains("embedding")
            ? .embedding
            : ModelCapability.role(inferringFrom: entry.name)
        return ModelRecommendation(
            id: "ollama:\(entry.name)", name: entry.name, source: sourceName, runtime: "Ollama", role: role,
            quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown",
            compatibility: ControllerPolicy.compatibility(
                sizeBytes: nil, architectureKnown: false, gated: false,
                multimodal: multimodal, cloudOnly: cloudOnly
            ),
            rationale: Self.rationale(badges: entry.badges, multimodal: multimodal, cloudOnly: cloudOnly),
            updatedAt: nil,
            // Tagless, exactly as the library publishes it. Selection matching
            // normalizes the tag, so this does not create a duplicate entry.
            modelName: entry.name
        )
    }

    private static func rationale(badges: Set<String>, multimodal: Bool, cloudOnly: Bool) -> String {
        if multimodal { return "Multimodal model; this controller manages text-only services." }
        if cloudOnly { return "Cloud-only model; it has no local weights to run." }
        guard !badges.isEmpty else {
            return "Official Ollama listing found, but variant size and license require verification; no action is offered."
        }
        let listed = badges.sorted().joined(separator: ", ")
        return "Official Ollama listing reporting \(listed). Variant size and license require verification; no action is offered."
    }

    private static let requestTimeout: TimeInterval = 20
    private static let listingURL = URL(string: "https://ollama.com/library?sort=newest")!
}