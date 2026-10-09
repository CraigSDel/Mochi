import Foundation
import XCTest
@testable import LocalAIController

@MainActor
final class ServiceProcessControllerTests: XCTestCase {
    func test_makeProcess_configuresOutputAndTracksProcess() throws {
        let factory = FakeProcessFactory()
        let controller = ServiceProcessController(factory: factory)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let process = controller.makeProcess(for: .llamaChat, output: handle) { _ in }
        controller.register(process, for: .llamaChat)

        XCTAssertNotNil(process.standardOutput)
        XCTAssertTrue(controller.process(for: .llamaChat) === process)
        XCTAssertNotNil(controller.outputHandles[.llamaChat])
    }

    func test_stopRequest_isTrackedAndCompleted() {
        let controller = ServiceProcessController(factory: FakeProcessFactory())

        controller.requestStop(for: .ollama)
        XCTAssertTrue(controller.wasStopRequested(for: .ollama))

        controller.completeStop(for: .ollama)

        XCTAssertFalse(controller.wasStopRequested(for: .ollama))
        XCTAssertNil(controller.process(for: .ollama))
    }
}
