import XCTest

final class RepositoryHygieneTests: XCTestCase {
    func testNoAuthoredFileExceeds300Lines() throws {
        let script = try locateLineLengthScript()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "Files exceeding 300 lines:\n\(text)")
    }

    private func locateLineLengthScript() throws -> URL {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let script = candidate.appendingPathComponent("check_code_line_lengths.sh")
            if fileManager.fileExists(atPath: script.path) { return script }
            candidate = candidate.deletingLastPathComponent()
        }
        throw CocoaError(.fileReadNoPermission)
    }
}