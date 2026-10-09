import XCTest

final class AuthoredFilePolicyTests: XCTestCase {
    func testNoAuthoredFileExceeds250Lines() throws {
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
        XCTAssertEqual(process.terminationStatus, 0, "Files exceeding 250 lines:\n\(text)")
    }

    func testLaunchersDoNotInstallOrElevateAndConsumeAutocompleteLimit() throws {
        let root = try repositoryRoot()
        let llama = try String(contentsOf: root.appendingPathComponent("start_llama_network.sh"))
        XCTAssertFalse(llama.contains("brew install"))
        XCTAssertFalse(llama.contains("sudo "))
        XCTAssertTrue(llama.contains("PREDICT_LIMIT=\"$MAX_OUTPUT\""))
        XCTAssertTrue(llama.contains("PREDICT_LIMIT=\"$OUTPUT_LIMIT\""))
    }

    func testLaunchersExposeEveryConfiguredRuntimeTuningContract() throws {
        let root = try repositoryRoot()
        let llama = try String(contentsOf: root.appendingPathComponent("start_llama_network.sh"))

        for name in [
            "GPU_LAYERS", "FLASH_ATTENTION", "KV_CACHE_KEY", "KV_CACHE_VALUE",
            "CACHE_REUSE", "BATCH", "UBATCH", "THREADS", "THREADS_BATCH",
            "MAX_OUTPUT_TOKENS", "TEMPERATURE", "TOP_K", "TOP_P",
            "REPEAT_PENALTY", "AUTOCOMPLETE_OUTPUT_LIMIT"
        ] {
            XCTAssertTrue(llama.contains(name), "llama launcher is missing (name)")
        }
        for bindMode in ["tailscale", "localhost", "lan"] {
            XCTAssertTrue(llama.contains(bindMode))
        }
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

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) { return candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        throw CocoaError(.fileReadNoPermission)
    }
}

