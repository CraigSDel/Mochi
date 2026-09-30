import Foundation
import Combine
import UserNotifications

protocol RecommendationProvider: Sendable {
    var sourceName: String { get }
    func fetch() async throws -> [ModelRecommendation]
}

struct HuggingFaceProvider: RecommendationProvider {
    let sourceName = "Hugging Face"

    private struct HFModel: Decodable, Sendable {
        struct Sibling: Decodable, Sendable { let rfilename: String; let size: Int64? }
        let id: String
        let tags: [String]?
        let gated: FlexibleGated?
        let `private`: Bool?
        let lastModified: Date?
        let siblings: [Sibling]?
    }

    private enum FlexibleGated: Decodable, Sendable {
        case bool(Bool), text(String)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
            else { self = .text((try? value.decode(String.self)) ?? "unknown") }
        }
        var isGated: Bool { if case .bool(false) = self { return false }; return true }
    }

    func fetch() async throws -> [ModelRecommendation] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            .init(name: "filter", value: "gguf"), .init(name: "sort", value: "lastModified"),
            .init(name: "direction", value: "-1"), .init(name: "limit", value: "50"), .init(name: "full", value: "true")
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let summaries = try decoder.decode([HFModel].self, from: data)
        var detailed: [HFModel] = []
        for summary in summaries.prefix(20) {
            let lower = ([summary.id] + (summary.tags ?? [])).joined(separator: " ").lowercased()
            guard ControllerPolicy.supportedArchitectures.contains(where: { lower.contains($0) }),
                  !lower.contains("vision"), !lower.contains("multimodal") else {
                detailed.append(summary); continue
            }
            var detailComponents = URLComponents(string: "https://huggingface.co/api/models/\(summary.id)")!
            detailComponents.queryItems = [.init(name: "files_metadata", value: "true")]
            if let detailURL = detailComponents.url,
               let (detailData, detailResponse) = try? await URLSession.shared.data(from: detailURL),
               (detailResponse as? HTTPURLResponse)?.statusCode == 200,
               let detail = try? decoder.decode(HFModel.self, from: detailData) {
                detailed.append(detail)
            } else {
                detailed.append(summary)
            }
        }
        detailed.append(contentsOf: summaries.dropFirst(20))
        return detailed.map(classify)
    }

    private func classify(_ model: HFModel) -> ModelRecommendation {
        let tags = model.tags ?? []
        let lower = ([model.id] + tags).joined(separator: " ").lowercased()
        let files = (model.siblings ?? []).filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
        let candidate = files
            .filter { name in ["q4_k_m", "q4_k_s", "q5_k_m", "q5_k_s"].contains { name.rfilename.lowercased().contains($0) } }
            .filter { ($0.size ?? Int64.max) <= Int64(ControllerPolicy.maxModelBytes) }
            .sorted { ($0.size ?? .max) < ($1.size ?? .max) }.first
        let architecture = ControllerPolicy.supportedArchitectures.first { lower.contains($0) }
        let state = ControllerPolicy.compatibility(sizeBytes: candidate?.size, architectureKnown: architecture != nil, gated: model.private == true || model.gated?.isGated == true, multimodal: lower.contains("vision") || lower.contains("multimodal"), cloudOnly: false)
        let reason: String
        if model.private == true || model.gated?.isGated == true { reason = "Gated or private models are excluded." }
        else if lower.contains("vision") || lower.contains("multimodal") { reason = "Multimodal models are excluded from this text-only controller." }
        else if architecture == nil { reason = "Architecture is not on the maintained llama.cpp allowlist." }
        else if candidate == nil { reason = "No supported, sized Q4/Q5 GGUF variant was reported." }
        else if !ControllerPolicy.fits(sizeBytes: candidate?.size) { reason = "The model exceeds the conservative memory budget." }
        else { reason = "Known llama.cpp architecture and a local-sized GGUF with system memory reserved." }
        return ModelRecommendation(
            id: "hf:\(model.id)", name: model.id, source: sourceName, runtime: "llama.cpp",
            role: role(for: lower), quantization: quantization(from: candidate?.rfilename), sizeBytes: candidate?.size,
            context: "See model metadata", license: tags.first(where: { $0.hasPrefix("license:") })?.replacingOccurrences(of: "license:", with: "") ?? "Unknown",
            compatibility: state, rationale: reason, updatedAt: model.lastModified,
            repository: candidate == nil ? nil : model.id, filename: candidate?.rfilename
        )
    }

    private func role(for text: String) -> RecommendationRole {
        if text.contains("embed") { return .embedding }
        if text.contains("coder") || text.contains("code") { return .coding }
        return .chat
    }

    private func quantization(from file: String?) -> String {
        guard let file else { return "Unknown" }
        return ["Q4_K_M", "Q4_K_S", "Q5_K_M", "Q5_K_S"].first { file.uppercased().contains($0) } ?? "GGUF"
    }
}

struct OllamaLibraryProvider: RecommendationProvider {
    let sourceName = "Ollama Library"

    func fetch() async throws -> [ModelRecommendation] {
        let url = URL(string: "https://ollama.com/library?sort=newest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        let regex = try NSRegularExpression(pattern: #"href=[\"']\/library\/([a-zA-Z0-9._-]+)[\"']"#)
        let range = NSRange(html.startIndex..., in: html)
        var names: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: html) else { continue }
            let name = String(html[swiftRange])
            if !names.contains(name) { names.append(name) }
            if names.count == 30 { break }
        }
        return names.map { name in
            let lower = name.lowercased()
            return ModelRecommendation(
                id: "ollama:\(name)", name: name, source: sourceName, runtime: "Ollama", role: role(for: lower),
                quantization: "Unknown", sizeBytes: nil, context: "Unknown", license: "Unknown",
                compatibility: .unverified,
                rationale: "Official Ollama listing found, but variant size and license require verification; no action is offered.", updatedAt: nil,
                modelName: name
            )
        }
    }

    private func role(for text: String) -> RecommendationRole {
        if text.contains("embed") { return .embedding }
        if text.contains("coder") || text.contains("code") { return .coding }
        return .chat
    }
}

struct CuratedLlamaCppProvider: RecommendationProvider {
    let sourceName = "Verified llama.cpp"

    static var recommendations: [ModelRecommendation] {
        [
            recommendation(
                id: "qwen3.8-27b-q4", name: "Qwen3.8 27B Q4", role: .chat,
                repository: "unsloth/Qwen3.8-27B-GGUF", filename: "Qwen3.8-27B-UD-Q4_K_M.gguf",
                sizeBytes: 16_460_000_000, quantization: "Q4_K_M", license: "Apache-2.0"
            ),
            recommendation(
                id: "qwen2.5-coder-1.5b-q4", name: "Qwen2.5 Coder 1.5B Q4", role: .coding,
                repository: "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF", filename: "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                sizeBytes: 1_120_000_000, quantization: "Q4_K_M", license: "Apache-2.0"
            ),
            recommendation(
                id: "nomic-embed-v1.5-q8", name: "Nomic Embed Text v1.5 Q8", role: .embedding,
                repository: "nomic-ai/nomic-embed-text-v1.5-GGUF", filename: "nomic-embed-text-v1.5.Q8_0.gguf",
                sizeBytes: 146_000_000, quantization: "Q8_0", license: "Apache-2.0"
            )
        ]
    }

    func fetch() async throws -> [ModelRecommendation] { Self.recommendations }

    private static func recommendation(id: String, name: String, role: RecommendationRole, repository: String, filename: String, sizeBytes: Int64, quantization: String, license: String) -> ModelRecommendation {
        let compatibility = ControllerPolicy.compatibility(sizeBytes: sizeBytes, architectureKnown: true, gated: false, multimodal: false, cloudOnly: false)
        return ModelRecommendation(
            id: "curated:\(id)", name: name, source: "Verified llama.cpp", runtime: "llama.cpp", role: role,
            quantization: quantization, sizeBytes: sizeBytes, context: "Verified GGUF", license: license,
            compatibility: compatibility, rationale: "Verified text-only GGUF for llama.cpp, sized against this Mac's conservative memory budget.", updatedAt: nil,
            repository: repository, filename: filename
        )
    }
}

@MainActor
final class RecommendationStore: ObservableObject {
    @Published private(set) var recommendations: [ModelRecommendation] = []
    @Published private(set) var status = "Not checked yet"
    @Published private(set) var isRefreshing = false
    @Published var lastChecked: Date?

    private let providers: [any RecommendationProvider]
    private let defaults: UserDefaults
    private let cacheURL: URL
    private var timer: Timer?

    init(
        providers: [any RecommendationProvider] = [CuratedLlamaCppProvider(), HuggingFaceProvider(), OllamaLibraryProvider()],
        defaults: UserDefaults = .standard,
        cacheURL: URL? = nil,
        startTimer: Bool = true
    ) {
        self.providers = providers
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Local AI Controller")
        self.cacheURL = cacheURL ?? base.appendingPathComponent("recommendations.json")
        loadCache()
        mergeCuratedRecommendationsIfEnabled()
        let stored = defaults.object(forKey: "recommendationsLastChecked") as? Date
        lastChecked = stored
        if stored == nil || Date().timeIntervalSince(stored!) >= 86_400 { Task { await refresh() } }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lastChecked == nil || Date().timeIntervalSince(self.lastChecked!) >= 86_400 else { return }
                await self.refresh()
            }
        } }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var combined: [ModelRecommendation] = []
        var failures: [String] = []
        var succeeded: Set<String> = []
        await withTaskGroup(of: (String, Result<[ModelRecommendation], Error>).self) { group in
            for provider in providers {
                group.addTask {
                    do { return (provider.sourceName, .success(try await provider.fetch())) }
                    catch { return (provider.sourceName, .failure(error)) }
                }
            }
            for await (name, result) in group {
                switch result {
                case .success(let models): combined += models; succeeded.insert(name)
                case .failure: failures.append(name)
                }
            }
        }
        guard !succeeded.isEmpty else {
            status = "Unavailable: \(failures.joined(separator: ", "))"; return
        }
        let retained = recommendations.filter { !succeeded.contains($0.source) }
        combined += retained
        let previous = Set(recommendations.map(\.id))
        recommendations = combined.sorted { lhs, rhs in
            if lhs.compatibility != rhs.compatibility { return lhs.compatibility.rawValue < rhs.compatibility.rawValue }
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        let newCompatible = combined.filter { $0.compatibility == .compatible && !previous.contains($0.id) }
        if !newCompatible.isEmpty && !previous.isEmpty { await notify(newCompatible) }
        lastChecked = Date(); defaults.set(lastChecked, forKey: "recommendationsLastChecked")
        status = failures.isEmpty ? "Checked both registries" : "Unavailable: \(failures.joined(separator: ", "))"
        saveCache()
    }

    private func notify(_ models: [ModelRecommendation]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = "New compatible local models"
        content.body = models.prefix(3).map(\.name).joined(separator: ", ")
        try? await center.add(UNNotificationRequest(identifier: "models-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil))
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([ModelRecommendation].self, from: data) else { return }
        recommendations = decoded
    }
    private func mergeCuratedRecommendationsIfEnabled() {
        guard providers.contains(where: { $0.sourceName == CuratedLlamaCppProvider().sourceName }) else { return }
        let curatedIDs = Set(CuratedLlamaCppProvider.recommendations.map(\.id))
        recommendations.removeAll { curatedIDs.contains($0.id) }
        recommendations.insert(contentsOf: CuratedLlamaCppProvider.recommendations, at: 0)
    }
    private func saveCache() {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(recommendations) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
