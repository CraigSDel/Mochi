import Foundation
import XCTest
@testable import LocalAIController

final class ServiceStoreTests: XCTestCase {
    func test_processStore_roundTripsAndRemovesRecords() throws {
        let directory = try makeDirectory()
        let store = FileManagedProcessStore(directory: directory)
        let record = ManagedProcessRecord(
            serviceID: .llamaChat,
            pid: 42,
            port: 11437,
            expectedCommand: "bash start_llama_network.sh",
            startedAt: Date(),
            logPath: directory.appendingPathComponent("llamaChat.log").path,
            bindMode: .localhost
        )

        store.save(record)

        XCTAssertEqual(store.load(.llamaChat)?.pid, 42)
        store.remove(.llamaChat)
        XCTAssertNil(store.load(.llamaChat))
    }

    func test_processStore_readsLegacyRecordWithoutBindMode() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("processes.json")
        let json = #"[{"serviceID":"llamaChat","pid":42,"port":11437,"expectedCommand":"start_llama_network.sh","startedAt":0,"logPath":"/tmp/test.log"}]"#
        try Data(json.utf8).write(to: url)

        let record = FileManagedProcessStore(directory: directory).load(.llamaChat)

        XCTAssertNil(record?.bindMode)
        XCTAssertEqual(record?.expectedCommand, "start_llama_network.sh")
    }

    func test_logStore_appendsTailsAndClears() throws {
        let directory = try makeDirectory()
        let store = FileServiceLogStore(directory: directory)

        store.append("first", to: .llamaChat, handle: nil)
        store.append("second", to: .llamaChat, handle: nil)
        XCTAssertTrue(store.tail(.llamaChat).contains("first"))
        XCTAssertTrue(store.tail(.llamaChat).contains("second"))

        store.clear(.llamaChat, handle: nil)

        XCTAssertEqual(store.tail(.llamaChat), "")
    }

    func test_configurationStore_roundTripsAndReadsLegacyPort() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(12001, forKey: "llamaChatPort")
        let store = UserDefaultsServiceConfigurationStore(defaults: defaults)
        let configuration = ServiceLaunchConfiguration.defaultValue(for: .llamaChat)

        store.save([.llamaChat: configuration])

        XCTAssertEqual(store.load()?[.llamaChat], configuration)
        XCTAssertEqual(store.legacyChatPort(), 12001)
    }

    func test_downloadQueueStore_roundTripsQueue() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = UserDefaultsModelDownloadQueueStore(defaults: defaults)
        let model = ModelRecommendation(
            id: "test", name: "Test", source: "Test", runtime: "llama.cpp", role: .chat,
            quantization: "Q4", sizeBytes: 10, context: "test", license: "MIT",
            compatibility: .compatible, rationale: "test", updatedAt: nil
        )

        await store.save([model])

        let loaded = await store.load()
        XCTAssertEqual(loaded, [model])
    }

    func test_recommendationCache_handlesMissingFileAndRoundTripsRecommendations() throws {
        let directory = try makeDirectory()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = FileRecommendationCache(
            defaults: defaults,
            cacheURL: directory.appendingPathComponent("recommendations.json")
        )
        let model = ModelRecommendation(
            id: "cached", name: "Cached", source: "Test", runtime: "llama.cpp", role: .chat,
            quantization: "Q4", sizeBytes: 10, context: "test", license: "MIT",
            compatibility: .compatible, rationale: "test", updatedAt: nil
        )

        XCTAssertEqual(cache.load(), [])
        cache.save([model])

        XCTAssertEqual(cache.load(), [model])
        cache.setLastChecked(Date(timeIntervalSince1970: 42))
        XCTAssertEqual(cache.lastChecked(), Date(timeIntervalSince1970: 42))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServiceStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
