import Foundation

extension ServiceManager {
    func captureRuntimeIdentity(for record: ManagedProcessRecord) async {
        guard await probe.isProcessRunning(record.pid) else { return }
        let command = await probe.processCommand(record.pid).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        save(.init(serviceID: record.serviceID, pid: record.pid, port: record.port, expectedCommand: record.expectedCommand, runtimeCommand: command, startedAt: record.startedAt, logPath: record.logPath, bindMode: record.bindMode))
    }
}
