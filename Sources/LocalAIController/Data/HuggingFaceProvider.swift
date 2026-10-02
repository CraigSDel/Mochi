import Foundation

struct HFModel: Decodable, Sendable {
    struct Sibling: Decodable, Sendable { let rfilename: String; let size: Int64? }
    let id: String
    let tags: [String]?
    let pipelineTag: String?
    let gated: FlexibleGated?
    let `private`: Bool?
    let lastModified: Date?
    let siblings: [Sibling]?

    enum CodingKeys: String, CodingKey {
        case id, tags, gated, siblings
        case pipelineTag = "pipeline_tag"
        case `private`
        case lastModified = "lastModified"
    }

    var isGated: Bool { `private` == true || gated?.isGated == true }
    var isMultimodal: Bool {
        ModelCapability.isMultimodal(pipelineTag: pipelineTag, tags: tags ?? [], filenames: (siblings ?? []).map(\.rfilename))
    }
    var supportedArchitecture: String? {
        let lower = ([id] + (tags ?? [])).joined(separator: " ").lowercased()
        return ControllerPolicy.supportedArchitectures.first { lower.contains($0) }
    }
    /// Prefilter hit: only these are worth a detail request, because a file
    /// listing with real byte sizes is the only route to `.compatible`.
    var needsDetail: Bool { supportedArchitecture != nil && !isMultimodal }
}

enum FlexibleGated: Decodable, Sendable {
    case bool(Bool), text(String)
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else { self = .text((try? value.decode(String.self)) ?? "unknown") }
    }
    var isGated: Bool { if case .bool(false) = self { return false }; return true }
}

struct HuggingFaceProvider: RecommendationProvider {
    let sourceName = "Hugging Face"
    static let detailConcurrencyLimit = 4
    static let requestTimeout: TimeInterval = 20
    private let fetcher: any HTTPFetching

    init(fetcher: any HTTPFetching = URLSessionFetching()) { self.fetcher = fetcher }

    func fetch() async throws -> [ModelRecommendation] {
        let summaries = try await load(Self.summariesURL())
        let detailed = await resolveDetails(for: summaries)
        return summaries.indices.map { detailed[$0] ?? summaries[$0] }.map(classify)
    }

    /// Fetches metadata for every prefiltered candidate rather than a fixed
    /// prefix, so a known-architecture model below the old rank-20 cut-off is
    /// still verifiable. Results are keyed by input index so the emitted order
    /// stays deterministic regardless of completion order.
    private func resolveDetails(for summaries: [HFModel]) async -> [Int: HFModel] {
        let pending = summaries.indices.filter { summaries[$0].needsDetail }
        guard !pending.isEmpty else { return [:] }
        let fetcher = fetcher
        let resolved = await withTaskGroup(of: (Int, HFModel).self, returning: [(index: Int, model: HFModel)].self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<min(Self.detailConcurrencyLimit, pending.count) {
                if let index = iterator.next() {
                    group.addTask { (index, await Self.detail(for: summaries[index], using: fetcher)) }
                }
            }
            var collected: [(index: Int, model: HFModel)] = []
            while let (index, model) = await group.next() {
                collected.append((index, model))
                if let next = iterator.next() {
                    group.addTask { (next, await Self.detail(for: summaries[next], using: fetcher)) }
                }
            }
            return collected
        }
        return resolved.reduce(into: [:]) { $0[$1.index] = $1.model }
    }

    private static func detail(for summary: HFModel, using fetcher: any HTTPFetching) async -> HFModel {
        var components = URLComponents(string: "https://huggingface.co/api/models/\(summary.id)")!
        components.queryItems = [.init(name: "files_metadata", value: "true")]
        guard let url = components.url else { return summary }
        do {
            let response = try await fetcher.fetch(url, timeout: requestTimeout)
            guard response.isSuccess else { return summary }
            return (try? makeDecoder().decode(HFModel.self, from: response.data)) ?? summary
        } catch {
            return summary
        }
    }

    private func load(_ url: URL) async throws -> [HFModel] {
        let response = try await fetcher.fetch(url, timeout: Self.requestTimeout)
        guard response.isSuccess else { throw URLError(.badServerResponse) }
        return try Self.makeDecoder().decode([HFModel].self, from: response.data)
    }

    private func classify(_ model: HFModel) -> ModelRecommendation {
        let tags = model.tags ?? []
        let lower = ([model.id] + tags).joined(separator: " ").lowercased()
        let candidate = Self.preferredCandidate(model.siblings ?? [])
        let architectureKnown = model.supportedArchitecture != nil
        let state = ControllerPolicy.compatibility(
            sizeBytes: candidate?.size,
            architectureKnown: architectureKnown,
            gated: model.isGated,
            multimodal: model.isMultimodal,
            cloudOnly: false
        )
        return ModelRecommendation(
            id: "hf:\(model.id)", name: model.id, source: sourceName, runtime: "llama.cpp",
            role: ModelCapability.role(inferringFrom: lower),
            quantization: Self.quantization(from: candidate?.rfilename), sizeBytes: candidate?.size,
            context: "See model metadata",
            license: tags.first(where: { $0.hasPrefix("license:") })?.replacingOccurrences(of: "license:", with: "") ?? "Unknown",
            compatibility: state,
            rationale: Self.rationale(isGated: model.isGated, multimodal: model.isMultimodal, architectureKnown: architectureKnown, candidate: candidate),
            updatedAt: model.lastModified,
            repository: candidate == nil ? nil : model.id, filename: candidate?.rfilename
        )
    }

    static func preferredCandidate(_ siblings: [HFModel.Sibling]) -> HFModel.Sibling? {
        siblings
            .filter { name in ["q4_k_m", "q4_k_s", "q5_k_m", "q5_k_s"].contains { name.rfilename.lowercased().contains($0) } }
            .filter { ($0.size ?? Int64.max) <= Int64(ControllerPolicy.maxModelBytes) }
            .sorted { ($0.size ?? .max) < ($1.size ?? .max) }.first
    }

    private static func rationale(isGated: Bool, multimodal: Bool, architectureKnown: Bool, candidate: HFModel.Sibling?) -> String {
        if isGated { return "Gated or private models are excluded." }
        if multimodal { return "Multimodal models are excluded from this text-only controller." }
        if !architectureKnown { return "Architecture is not on the maintained llama.cpp allowlist." }
        if candidate == nil { return "No supported, sized Q4/Q5 GGUF variant was reported." }
        if !ControllerPolicy.fits(sizeBytes: candidate?.size) { return "The model exceeds the conservative memory budget." }
        return "Known llama.cpp architecture and a local-sized GGUF with system memory reserved."
    }

    private static func quantization(from file: String?) -> String {
        guard let file else { return "Unknown" }
        return ["Q4_K_M", "Q4_K_S", "Q5_K_M", "Q5_K_S"].first { file.uppercased().contains($0) } ?? "GGUF"
    }

    private static func summariesURL() -> URL {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            .init(name: "filter", value: "gguf"), .init(name: "sort", value: "lastModified"),
            .init(name: "direction", value: "-1"), .init(name: "limit", value: "50"), .init(name: "full", value: "true")
        ]
        return components.url!
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}