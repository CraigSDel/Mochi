import Foundation

@MainActor
enum ManagedProcessOwnership {
    static func processIDs(from roots: [ServiceID: ManagedProcessRoot]) -> [ServiceID: Int32] {
        Dictionary(uniqueKeysWithValues: roots.compactMap { serviceID, root in
            guard case .owned(let pid) = root else { return nil }
            return (serviceID, pid)
        })
    }

    static func roots(records: [ManagedProcessRecord], probe: any SystemProbing) -> [ServiceID: ManagedProcessRoot] {
        roots(
            serviceIDs: ServiceID.allCases,
            records: records,
            isProcessRunning: { probe.isProcessRunning($0) },
            processCommand: { probe.processCommand($0) }
        )
    }

    static func root(_ record: ManagedProcessRecord, probe: any SystemProbing) -> ManagedProcessRoot {
        root(record, isProcessRunning: { probe.isProcessRunning($0) }, processCommand: { probe.processCommand($0) })
    }

    static func roots(
        serviceIDs: [ServiceID],
        records: [ManagedProcessRecord],
        isProcessRunning: (Int32) -> Bool,
        processCommand: (Int32) -> String
    ) -> [ServiceID: ManagedProcessRoot] {
        Dictionary(uniqueKeysWithValues: serviceIDs.map { serviceID in
            let record = records.first { $0.serviceID == serviceID }
            return (serviceID, root(record, isProcessRunning: isProcessRunning, processCommand: processCommand))
        })
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
        let command = processCommand(record.pid)
        let matches = command.contains(record.expectedCommand) || command.contains("llama-server") ||
            (record.serviceID == .ollama && command.contains("bash"))
        guard matches else {
            return .noOwnedPID(reason: "Recorded PID \(record.pid) command does not match the expected runtime")
        }
        return .owned(pid: record.pid)
    }
}