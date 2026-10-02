import Foundation

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