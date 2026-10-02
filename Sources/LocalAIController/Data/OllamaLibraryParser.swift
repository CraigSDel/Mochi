import Foundation

/// One row of the Ollama library index page.
struct OllamaLibraryEntry: Hashable, Sendable {
    let name: String
    /// Recognized capability badges only: `vision`, `audio`, `embedding`,
    /// `tools`, `thinking`, `cloud`. Parameter-count badges (`27b`) are not
    /// capabilities and are never converted into byte sizes.
    let badges: Set<String>
}

/// Parses `https://ollama.com/library` without any networking so the mapping can
/// be exercised directly in tests.
///
/// The contract is deliberately fail-soft: a block that cannot be read yields no
/// entry instead of aborting the page, so a markup change degrades to "no
/// capability data" rather than "no recommendations".
enum OllamaLibraryParser {
    /// Maximum rows promoted to recommendations.
    static let entryLimit = 30

    static func entries(html: String, limit: Int = OllamaLibraryParser.entryLimit) -> [OllamaLibraryEntry] {
        guard let blockPattern = try? NSRegularExpression(pattern: #"<li\b.*?</li>"#, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen: Set<String> = []
        var results: [OllamaLibraryEntry] = []
        for match in blockPattern.matches(in: html, range: range) {
            guard let blockRange = Range(match.range, in: html) else { continue }
            let block = String(html[blockRange])
            guard let name = firstName(in: block), !name.isEmpty, seen.insert(name).inserted else { continue }
            results.append(.init(name: name, badges: badges(in: block)))
            if results.count == limit { break }
        }
        return results
    }

    private static func firstName(in block: String) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: #"href=["']/library/([A-Za-z0-9._-]+)["']"#),
              let match = pattern.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let nameRange = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[nameRange])
    }

    /// Reads badge *text* rather than the Tailwind classes used to color it, so
    /// a class rename does not silently change semantics.
    private static func badges(in block: String) -> Set<String> {
        guard let pattern = try? NSRegularExpression(pattern: #"<span\b[^>]*\brounded-md\b[^>]*>(.*?)</span>"#, options: [.dotMatchesLineSeparators]) else { return [] }
        var found: Set<String> = []
        for match in pattern.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
            guard let innerRange = Range(match.range(at: 1), in: block) else { continue }
            let text = stripTags(String(block[innerRange])).lowercased()
            if ModelCapability.capabilityBadges.contains(text) { found.insert(text) }
        }
        return found
    }

    private static func stripTags(_ value: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"<[^>]*>"#, options: [.dotMatchesLineSeparators]) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return pattern.stringByReplacingMatches(in: value, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}