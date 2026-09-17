import Foundation

@MainActor
protocol SystemProbing: AnyObject {
    var supportDirectory: URL { get }
    var physicalMemory: UInt64 { get }
    func commandPath(_ command: String) -> String?
    func isPortListening(_ port: Int) -> Bool
    func tailscaleIP() -> String?
    func availableDiskBytes() -> Int64
    func scriptURL(named name: String) -> URL?
    func isProcessRunning(_ pid: Int32) -> Bool
    func processCommand(_ pid: Int32) -> String
    func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool
}

@MainActor
final class LiveSystemProbe: SystemProbing {
    private let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }
    var supportDirectory: URL { fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Local AI Controller") }
    var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }
    func commandPath(_ command: String) -> String? {
        guard !command.isEmpty else { return nil }
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
    func isPortListening(_ port: Int) -> Bool { !(run("/usr/sbin/lsof", ["-nP", "-tiTCP:\(port)", "-sTCP:LISTEN"]) ?? "").isEmpty }
    func tailscaleIP() -> String? { guard let executable = commandPath("tailscale") else { return nil }; return run(executable, ["ip", "-4"])?.split(separator: "\n").first.map(String.init) }
    func availableDiskBytes() -> Int64 {
        guard let value = try? supportDirectory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else { return 0 }
        return Int64(value)
    }
    func scriptURL(named name: String) -> URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), fileManager.fileExists(atPath: url.path) { return url }
        let local = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(name)
        return fileManager.fileExists(atPath: local.path) ? local : nil
    }
    func isProcessRunning(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }
    func processCommand(_ pid: Int32) -> String { run("/bin/ps", ["-p", String(pid), "-o", "command="]) ?? "" }
    func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool {
        let path = id == .ollama ? "/api/tags" : "/health"
        guard let url = URL(string: "http://\(host):\(port)\(path)") else { return false }
        var request = URLRequest(url: url); request.timeoutInterval = 1
        do { let (_, response) = try await URLSession.shared.data(for: request); return (200..<500).contains((response as? HTTPURLResponse)?.statusCode ?? 0) } catch { return false }
    }
    private func run(_ executable: String, _ arguments: [String]) -> String? {
        guard fileManager.isExecutableFile(atPath: executable) else { return nil }
        let process = Process(); let pipe = Pipe(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor protocol ProcessMaking: AnyObject { func makeProcess() -> Process }
@MainActor final class LiveProcessFactory: ProcessMaking { func makeProcess() -> Process { Process() } }
