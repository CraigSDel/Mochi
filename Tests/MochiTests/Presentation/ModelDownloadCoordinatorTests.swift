import XCTest
@testable import Mochi

@MainActor
final class ModelDownloadCoordinatorTests: XCTestCase {
    func test_enqueueDeduplicatesAndProcessesFIFO() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let fake = BlockingModelManager()
        let manager = ServiceManager(modelManager: fake, defaults: defaults, startTimer: false)
        let coordinator = ModelDownloadCoordinator(
            manager: manager,
            queueStore: UserDefaultsModelDownloadQueueStore(defaults: defaults)
        )
        let first = recommendation(id: "first", filename: "first.gguf")
        let second = recommendation(id: "second", filename: "second.gguf")

        coordinator.enqueue(first)
        coordinator.enqueue(first)
        coordinator.enqueue(second)
        await eventually { coordinator.active?.recommendation.id == first.id && coordinator.queued.map(\.id) == [second.id] }
        await waitForCallCount(1, fake: fake)
        let callsAfterFirst = await fake.recordedCalls()
        XCTAssertEqual(callsAfterFirst, [first.id])

        await fake.release()
        await eventually { coordinator.active?.recommendation.id == second.id }
        await waitForCallCount(2, fake: fake)
        await fake.release()
        await eventually { coordinator.active == nil && coordinator.completed.map(\.id) == [first.id, second.id] }
        let maximumCalls = await fake.maximumCalls()
        XCTAssertEqual(maximumCalls, 1)
    }

    func test_legacyMetadataWithoutPinDecodesUnpinned() throws {
        let data = Data(#"{"alias":"Model","role":"Chat / reasoning","assignedServices":[]}"#.utf8)
        let metadata = try JSONDecoder().decode(ModelMetadata.self, from: data)
        XCTAssertFalse(metadata.isPinned)
    }

    private func recommendation(id: String, filename: String) -> ModelRecommendation {
        ModelRecommendation(
            id: id, name: id, source: "Test", runtime: "llama.cpp", role: .chat,
            quantization: "Q4", sizeBytes: 100, context: "test", license: "MIT",
            compatibility: .compatible, rationale: "test", updatedAt: nil,
            repository: "owner/models", filename: filename
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached")
    }

    private func waitForCallCount(_ count: Int, fake: BlockingModelManager) async {
        for _ in 0..<100 {
            if await fake.recordedCalls().count >= count { return }
            await Task.yield()
        }
        XCTFail("Download call was not observed")
    }
}

private actor BlockingModelManager: ModelManaging {
    private(set) var calls: [String] = []
    private(set) var activeCalls = 0
    private(set) var maximumConcurrentCalls = 0
    private var gates: [CheckedContinuation<Void, Never>] = []

    func discover() async -> [DiscoveredModel] { [] }
    func loadMetadata() async -> [String: ModelMetadata] { [:] }
    func saveMetadata(_ metadata: [String: ModelMetadata]) async {}
    func delete(_ model: DiscoveredModel) async throws {}

    func download(
        _ recommendation: ModelRecommendation,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        calls.append(recommendation.id)
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
        progress(.init(completedBytes: 50, expectedBytes: 100))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gates.append(continuation)
        }
        activeCalls -= 1
    }

    func release() {
        guard !gates.isEmpty else { return }
        gates.removeFirst().resume()
    }

    func recordedCalls() -> [String] { calls }
    func maximumCalls() -> Int { maximumConcurrentCalls }
}
