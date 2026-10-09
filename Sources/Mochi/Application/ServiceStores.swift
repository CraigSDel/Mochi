import Foundation

protocol ManagedProcessStoring: AnyObject {
    func load(_ serviceID: ServiceID) -> ManagedProcessRecord?
    func save(_ record: ManagedProcessRecord)
    func remove(_ serviceID: ServiceID)
}

final class FileManagedProcessStore: ManagedProcessStoring {
    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("processes.json")
    }

    func load(_ serviceID: ServiceID) -> ManagedProcessRecord? {
        allRecords().first { $0.serviceID == serviceID }
    }

    func save(_ record: ManagedProcessRecord) {
        var records = allRecords().filter { $0.serviceID != record.serviceID }
        records.append(record)
        write(records)
    }

    func remove(_ serviceID: ServiceID) {
        write(allRecords().filter { $0.serviceID != serviceID })
    }

    private func allRecords() -> [ManagedProcessRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ManagedProcessRecord].self, from: data)) ?? []
    }

    private func write(_ records: [ManagedProcessRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

protocol ServiceLogStoring: AnyObject {
    func logURL(for serviceID: ServiceID) -> URL
    func ensureLog(for serviceID: ServiceID)
    func openForAppending(_ serviceID: ServiceID) throws -> FileHandle
    func append(_ message: String, to serviceID: ServiceID, handle: FileHandle?)
    func tail(_ serviceID: ServiceID) -> String
    func clear(_ serviceID: ServiceID, handle: FileHandle?)
}

final class FileServiceLogStore: ServiceLogStoring {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func logURL(for serviceID: ServiceID) -> URL {
        directory.appendingPathComponent("\(serviceID.rawValue).log")
    }

    func ensureLog(for serviceID: ServiceID) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = logURL(for: serviceID).path
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }
    }

    func openForAppending(_ serviceID: ServiceID) throws -> FileHandle {
        ensureLog(for: serviceID)
        let handle = try FileHandle(forWritingTo: logURL(for: serviceID))
        try handle.seekToEnd()
        return handle
    }

    func append(_ message: String, to serviceID: ServiceID, handle: FileHandle?) {
        ensureLog(for: serviceID)
        let data = Data("[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n".utf8)
        if let handle {
            try? handle.write(contentsOf: data)
            return
        }
        guard let fallback = try? openForAppending(serviceID) else { return }
        try? fallback.write(contentsOf: data)
        try? fallback.close()
    }

    func tail(_ serviceID: ServiceID) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logURL(for: serviceID)) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let limit = UInt64(PerformanceBudgets.maximumServiceLogBytes)
        try? handle.seek(toOffset: size > limit ? size - limit : 0)
        return String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    func clear(_ serviceID: ServiceID, handle: FileHandle?) {
        if let handle {
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
        } else {
            try? Data().write(to: logURL(for: serviceID))
        }
    }
}
