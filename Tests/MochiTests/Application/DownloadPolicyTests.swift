import XCTest
@testable import Mochi

@MainActor
final class ModelDownloadPolicyTests: XCTestCase {
    func testMissingModelRequiresDownloadUntilPolicyChanges() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        probe.discoveredModels = [.init(runtime: .llamaCpp, name: "Cached", repository: "owner/repo", filename: "cached.gguf", sizeBytes: 1, roleHint: .chat, supportsVision: false)]
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        await manager.refreshModelInventory()
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

    func testRefreshReplacesPublishedInventory() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = FakeProbe(directory: directory)
        let manager = ServiceManager(probe: probe, defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false)
        XCTAssertTrue(manager.installedModels.isEmpty)
        probe.discoveredModels = [.init(runtime: .llamaCpp, name: "new", repository: "owner/new", filename: "new.gguf", sizeBytes: 1, roleHint: .chat, supportsVision: false)]
        await manager.refreshModelInventory()
        XCTAssertEqual(manager.installedModels.map(\.name), ["new"])
    }
}
