import Foundation

/// Single source of truth for capability derivation.
///
/// The recommendation providers and the installed-model scanner previously
/// carried three divergent copies of these rules; every signal now lands here
/// so a model is classified the same way whether it came from a registry page
/// or from a local manifest.
enum ModelCapability {
    /// Tags and badge labels that identify a multimodal model.
    static let multimodalMarkers: Set<String> = [
        "vision", "multimodal", "vlm", "audio",
        "image-text-to-text", "video-text-to-text",
        "llava", "idefics", "internvl", "moondream"
    ]

    /// Capability badges reported by a model catalog.
    static let capabilityBadges: Set<String> = ["vision", "audio", "embedding", "tools", "thinking", "cloud"]

    static func role(inferringFrom value: String) -> RecommendationRole {
        let lower = value.lowercased()
        if lower.contains("embed") || lower.contains("bert") { return .embedding }
        if lower.contains("coder") || lower.contains("code") || lower.contains("fim") { return .coding }
        return .chat
    }

    /// Multimodal detection from Hugging Face metadata and local filenames.
    ///
    /// `mmproj` is llama.cpp's multimodal projector file; its presence means the
    /// repository can serve images even when no tag or pipeline tag says so.
    static func isMultimodal(pipelineTag: String?, tags: [String], filenames: [String]) -> Bool {
        if let pipelineTag, multimodalPipelineTags.contains(pipelineTag.lowercased()) { return true }
        if tags.contains(where: { multimodalMarkers.contains($0.lowercased()) }) { return true }
        return filenames.contains {
            let name = $0.lowercased()
            return name.hasSuffix(".gguf") && name.contains("mmproj")
        }
    }

    /// Multimodal detection from catalog capability badges.
    ///
    /// `cloud` is handled separately by `isCloudOnly(badges:)`: a cloud-only
    /// model is rejected for a different reason than a local projector.
    static func isMultimodal(badges: Set<String>) -> Bool {
        badges.contains { badge in
            guard badge != "cloud" else { return false }
            return multimodalMarkers.contains(badge.lowercased())
        }
    }

    static func isCloudOnly(badges: Set<String>) -> Bool {
        badges.contains { $0.lowercased() == "cloud" }
    }

    private static let multimodalPipelineTags: Set<String> = ["image-text-to-text", "video-text-to-text"]
}
