import XCTest
@testable import LocalAIController

@MainActor
final class ModelDownloadPolicyTests: XCTestCase {
    func testMissingModelRequiresDownloadUntilPolicyChanges() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        probe.discoveredModels = [.init(runtime: .llamaCpp, name: "Cached", repository: "owner/repo", filename: "cached.gguf", sizeBytes: 1, roleHint: .chat, supportsVision: false)]
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        var configuration = manager.configuration(for: .llamaChat)
        configuration.llama?.repository = "owner/repo"
        configuration.llama?.filename = "missing.gguf"
        configuration.llama?.alias = "Missing"
        manager.updateConfiguration(configuration, for: .llamaChat)

        XCTAssertEqual(manager.modelsRequiringDownload(for: .llamaChat), ["Missing"])
        manager.enableDownloads(for: [.llamaChat])
        XCTAssertTrue(manager.modelsRequiringDownload(for: .llamaChat).isEmpty)
        XCTAssertEqual(manager.configuration(for: .llamaChat).downloadPolicy, .allowDownloads)
    }

    func testTaglessConfiguredOllamaNameIsFoundInTheInstalledInventory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        probe.discoveredModels = [.init(runtime: .ollama, name: "llava:latest", repository: nil, filename: nil, sizeBytes: 1, roleHint: .chat, supportsVision: false)]
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        var ollama = manager.configuration(for: .ollama).ollama!
        ollama.chatModel = "llava"; ollama.autocompleteModel = "llava"; ollama.embeddingModel = "llava"
        var configuration = manager.configuration(for: .ollama)
        configuration.ollama = ollama
        manager.updateConfiguration(configuration, for: .ollama)

        // Ollama resolves a bare name to :latest, so a cached-only launch must not
        // be blocked by a download prompt it can never satisfy.
        XCTAssertTrue(manager.modelsRequiringDownload(for: .ollama).isEmpty)
    }

    func testGenuinelyMissingOllamaNameStillRequiresDownload() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        probe.discoveredModels = [.init(runtime: .ollama, name: "llava:latest", repository: nil, filename: nil, sizeBytes: 1, roleHint: .chat, supportsVision: false)]
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        var ollama = manager.configuration(for: .ollama).ollama!
        ollama.chatModel = "llava:13b"; ollama.autocompleteModel = "llava:13b"; ollama.embeddingModel = "llava:13b"
        var configuration = manager.configuration(for: .ollama)
        configuration.ollama = ollama
        manager.updateConfiguration(configuration, for: .ollama)

        XCTAssertEqual(manager.modelsRequiringDownload(for: .ollama), ["llava:13b", "llava:13b", "llava:13b"])
    }

    func testRefreshReplacesPublishedInventory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        XCTAssertTrue(manager.installedModels.isEmpty)
        probe.discoveredModels = [.init(runtime: .ollama, name: "new:latest", repository: nil, filename: nil, sizeBytes: 1, roleHint: .chat, supportsVision: false)]
        manager.refreshModelInventory()
        XCTAssertEqual(manager.installedModels.map(\.name), ["new:latest"])
    }
}