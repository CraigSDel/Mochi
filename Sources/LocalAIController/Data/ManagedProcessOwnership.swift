import Foundation

@MainActor
enum ManagedProcessOwnership {
    static func root(_ record: ManagedProcessRecord, probe: any SystemProbing) async -> ManagedProcessRoot {
        guard await probe.isProcessRunning(record.pid) else {
            return .noOwnedPID(reason: "Recorded PID \(record.pid) is not running")
        }
        let command = await probe.processCommand(record.pid)
        return root(record, isProcessRunning: { _ in true }, processCommand: { _ in command })
    }

    static func root(
        _ record: ManagedProcessRecord?,
        isProcessRunning: (Int32) -> Bool,
        processCommand: (Int32) -> String
    ) -> ManagedProcessRoot {
        guard let record else { return .noOwnedPID(reason: "No launch record") }
        guard isProcessRunning(record.pid) else {
            return .noOwnedPID(reason: "Recorded PID \(record.pid) is not running")
        }
        let command = processCommand(record.pid).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let expected = (record.runtimeCommand ?? record.expectedCommand)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let legacyExactMatch = expected.count == 1 && command.count == 2 &&
            ["bash", "/bin/bash"].contains(command[0]) && command[1] == expected[0]
        let matches = (!expected.isEmpty && command == expected) || legacyExactMatch
        guard matches else {
            return .noOwnedPID(reason: "Recorded PID \(record.pid) command does not match the expected runtime")
        }
        return .owned(pid: record.pid)
    }
}
