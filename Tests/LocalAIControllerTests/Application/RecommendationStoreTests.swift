import XCTest
@testable import LocalAIController

@MainActor
final class RecommendationStoreTests: XCTestCase {
    func testCompleteProviderFailureRetainsCacheAndDoesNotAdvanceLastChecked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appendingPathComponent("recommendations.json")
        let cached = ModelRecommendation(
            id: "cached", name: "Cached", source: "Registry", runtime: "llama.cpp", role: .chat,
            quantization: "Q4_K_M", sizeBytes: 1_000, context: "test", license: "test",
            compatibility: .compatible, rationale: "test", updatedAt: nil
        )
        try JSONEncoder().encode([cached]).write(to: cache)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let provider = StubRecommendationProvider(sourceName: "Registry", result: .failure(URLError(.notConnectedToInternet)))
        let store = RecommendationStore(providers: [provider], defaults: defaults, cacheURL: cache, startTimer: false)
        await store.refresh()
        XCTAssertEqual(store.recommendations.map(\.id), ["cached"])
        XCTAssertNil(store.lastChecked)
        let persisted = try JSONDecoder().decode([ModelRecommendation].self, from: Data(contentsOf: cache))
        XCTAssertEqual(persisted.map(\.id), ["cached"])
    }

    func testCuratedRecommendationsMergeIntoExistingCacheImmediately() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appendingPathComponent("recommendations.json")
        try JSONEncoder().encode([ModelRecommendation(
            id: "cached", name: "Cached", source: "Registry", runtime: "llama.cpp", role: .chat,
            quantization: "Q4", sizeBytes: 1, context: "test", license: "test",
            compatibility: .compatible, rationale: "test", updatedAt: nil
        )]).write(to: cache)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(Date(), forKey: "recommendationsLastChecked")

        let store = RecommendationStore(providers: [CuratedLlamaCppProvider()], defaults: defaults, cacheURL: cache, startTimer: false)

        XCTAssertEqual(store.recommendations.filter { $0.source == "Verified llama.cpp" }.count, 3)
        XCTAssertTrue(store.recommendations.contains { $0.id == "cached" })
    }
}
