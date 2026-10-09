import Foundation

struct ManagedProcessRecord: Codable, Sendable {
    let serviceID: ServiceID
    let pid: Int32
    let port: Int
    let expectedCommand: String
    let runtimeCommand: String?
    let startedAt: Date
    let logPath: String
    let bindMode: BindMode?

    init(
        serviceID: ServiceID, pid: Int32, port: Int, expectedCommand: String,
        runtimeCommand: String? = nil, startedAt: Date, logPath: String,
        bindMode: BindMode?
    ) {
        self.serviceID = serviceID
        self.pid = pid
        self.port = port
        self.expectedCommand = expectedCommand
        self.runtimeCommand = runtimeCommand
        self.startedAt = startedAt
        self.logPath = logPath
        self.bindMode = bindMode
    }
}
