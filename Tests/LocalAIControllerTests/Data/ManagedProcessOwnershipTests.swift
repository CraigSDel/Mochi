import XCTest
@testable import LocalAIController

@MainActor
final class ManagedProcessOwnershipTests: XCTestCase {
    func test_reusedPID_withUnrelatedBash_isNotOwned() {
        let record = ManagedProcessRecord(
            serviceID: .llamaChat, pid: 42, port: 11437,
            expectedCommand: "/bin/bash /Applications/LocalAI/start_llama_network.sh --model chat --bind localhost",
            startedAt: Date(), logPath: "/tmp/service.log", bindMode: .localhost
        )
        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { _ in true },
            processCommand: { _ in "/bin/bash /tmp/unrelated.sh --model chat --bind localhost" }
        )
        XCTAssertEqual(root, .noOwnedPID(reason: "Recorded PID 42 command does not match the expected runtime"))
    }

    func test_reusedPID_withUnrelatedLlamaServer_isNotOwned() {
        let record = ManagedProcessRecord(
            serviceID: .autocomplete, pid: 43, port: 11435,
            expectedCommand: "/bin/bash /Applications/LocalAI/start_llama_network.sh --model autocomplete --bind localhost",
            startedAt: Date(), logPath: "/tmp/service.log", bindMode: .localhost
        )
        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { _ in true },
            processCommand: { _ in "/usr/local/bin/llama-server --port 9999" }
        )
        XCTAssertEqual(root, .noOwnedPID(reason: "Recorded PID 43 command does not match the expected runtime"))
    }

    func test_matchingLauncherAndArguments_areOwned() {
        let expected = "/bin/bash /Applications/LocalAI/start_ollama_network.sh --bind localhost --port 11434"
        let record = ManagedProcessRecord(
            serviceID: .ollama, pid: 44, port: 11434,
            expectedCommand: expected, startedAt: Date(),
            logPath: "/tmp/service.log", bindMode: .localhost
        )

        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { $0 == 44 },
            processCommand: { _ in expected }
        )

        XCTAssertEqual(root, .owned(pid: 44))
    }

    func test_execReplacedRuntimeCommand_isOwned() {
        let launcher = "/bin/bash /Applications/LocalAI/start_llama_network.sh --model chat --bind localhost"
        let runtime = "llama-server -hf unsloth/Qwen3.8-27B-GGUF -hff Qwen3.8-27B-UD-Q4_K_M.gguf --host 127.0.0.1 --port 11437"
        let record = ManagedProcessRecord(
            serviceID: .llamaChat, pid: 47, port: 11437,
            expectedCommand: launcher, runtimeCommand: runtime,
            startedAt: Date(), logPath: "/tmp/service.log", bindMode: .localhost
        )

        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { $0 == 47 }, processCommand: { _ in runtime }
        )

        XCTAssertEqual(root, .owned(pid: 47))
    }

    func test_execReplacedRuntimeCommandWithDifferentArguments_isNotOwned() {
        let record = ManagedProcessRecord(
            serviceID: .llamaChat, pid: 48, port: 11437,
            expectedCommand: "/bin/bash /Applications/LocalAI/start_llama_network.sh --model chat --bind localhost",
            runtimeCommand: "llama-server --host 127.0.0.1 --port 11437 --model expected.gguf",
            startedAt: Date(), logPath: "/tmp/service.log", bindMode: .localhost
        )

        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { _ in true },
            processCommand: { _ in "llama-server --host 127.0.0.1 --port 11435 --model expected.gguf" }
        )

        XCTAssertEqual(root, .noOwnedPID(reason: "Recorded PID 48 command does not match the expected runtime"))
    }

    func test_runtimeCommandRoundTripsAndLegacyRecordDefaultsToNil() throws {
        let record = ManagedProcessRecord(
            serviceID: .llamaChat, pid: 49, port: 11437,
            expectedCommand: "launcher", runtimeCommand: "llama-server --port 11437",
            startedAt: Date(), logPath: "/tmp/service.log", bindMode: .localhost
        )
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ManagedProcessRecord.self, from: encoded)
        XCTAssertEqual(decoded.runtimeCommand, record.runtimeCommand)

        let legacy = #"{"serviceID":"llamaChat","pid":50,"port":11437,"expectedCommand":"launcher","startedAt":0,"logPath":"/tmp/service.log"}"#
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .secondsSince1970
        let legacyRecord = try legacyDecoder.decode(ManagedProcessRecord.self, from: Data(legacy.utf8))
        XCTAssertNil(legacyRecord.runtimeCommand)
    }

    func test_matchingExecutableWithDifferentLauncherArguments_isNotOwned() {
        let record = ManagedProcessRecord(
            serviceID: .ollama, pid: 45, port: 11434,
            expectedCommand: "/bin/bash /Applications/LocalAI/start_ollama_network.sh --bind localhost --port 11434",
            startedAt: Date(), logPath: "/tmp/service.log", bindMode: .localhost
        )

        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { _ in true },
            processCommand: { _ in "/bin/bash /Applications/LocalAI/start_ollama_network.sh --bind lan --port 11434" }
        )

        XCTAssertEqual(root, .noOwnedPID(reason: "Recorded PID 45 command does not match the expected runtime"))
    }

    func test_stalePID_isNotOwnedEvenWhenCommandMatches() {
        let expected = "/bin/bash /Applications/LocalAI/start_ollama_network.sh --bind localhost --port 11434"
        let record = ManagedProcessRecord(
            serviceID: .ollama, pid: 46, port: 11434,
            expectedCommand: expected, startedAt: Date(),
            logPath: "/tmp/service.log", bindMode: .localhost
        )

        let root = ManagedProcessOwnership.root(
            record, isProcessRunning: { _ in false },
            processCommand: { _ in expected }
        )

        XCTAssertEqual(root, .noOwnedPID(reason: "Recorded PID 46 is not running"))
    }
}
