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
