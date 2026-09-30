import Foundation

/// Normalizes Ollama model names for comparison only.
///
/// Ollama resolves a bare name to `:latest`, and the library catalog publishes
/// tagless names while a local inventory reports tagged names. Saved
/// configuration is never rewritten; these helpers only stop the two spellings
/// of the same model from being treated as different models.
enum OllamaModelReference {
    static let defaultTag = "latest"

    /// `llava` and `llava:latest` both become `llava:latest`.
    ///
    /// A tag separator only counts when the colon appears after the last `/`, so
    /// `acme/model:8b` is tagged while a namespace colon cannot be mistaken for
    /// a tag boundary.
    static func canonical(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        guard let colon = value.lastIndex(of: ":"), colon > lastSeparatorIndex(value) else {
            return "\(value):\(defaultTag)"
        }
        return value
    }

    /// Case-insensitive comparison key for two Ollama model references.
    static func key(_ raw: String) -> String {
        canonical(raw).lowercased()
    }

    private static func lastSeparatorIndex(_ value: String) -> String.Index {
        value.lastIndex(of: "/") ?? value.startIndex
    }
}