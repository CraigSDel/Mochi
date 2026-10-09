import Foundation
@testable import LocalAIController

final class FakeProbe: SystemProbing, @unchecked Sendable {
    let supportDirectory: URL
    var physicalMemory: UInt64 = 36 * 1_073_741_824
    var commands: [String: String] = ["tailscale": "/fake/tailscale", "llama-server": "/fake/llama-server", "ollama": "/fake/ollama"]
    var occupiedPorts: Set<Int> = []
    var portListeningCheck: ((Int) -> Bool)?
    var tailnetIP: String? = "100.64.0.1"
    var wifiIPv4: String? = "192.168.1.10"
    var lanIP: String? = "192.168.1.10"
    var diskBytes: Int64 = 100_000_000_000
    var script: URL?
    var processRunning = false
    var processRunningCheck: ((Int32) -> Bool)?
    var processCommandValue = "bash start_llama_network.sh"
    var healthy = false
    var lastHealthPort: Int?
    var lastHealthHost: String?
    var discoveredModels: [DiscoveredModel] = []
    var hardware = HardwareProfile.unavailable
    var diagnostic = TailscaleDiagnostic(status: .direct, peer: "test-peer", detail: "direct", checkedAt: Date())
    var diagnosticCallCount = 0
    init(directory: URL) { supportDirectory = directory }
    func commandPath(_ command: String) async -> String? { await MainActor.run { commands[command] } }
    func isPortListening(_ port: Int) async -> Bool {
        await MainActor.run { portListeningCheck?(port) ?? occupiedPorts.contains(port) }
    }
    func tailscaleIP() async -> String? { await MainActor.run { tailnetIP } }
    func wifiIP() async -> String? { await MainActor.run { wifiIPv4 } }
    func localNetworkIP() async -> String? { await MainActor.run { lanIP } }
    func availableDiskBytes() async -> Int64 { await MainActor.run { diskBytes } }
    func scriptURL(named name: String) async -> URL? { await MainActor.run { script } }
    func isProcessRunning(_ pid: Int32) async -> Bool {
        await MainActor.run { processRunningCheck?(pid) ?? processRunning }
    }
    func processCommand(_ pid: Int32) async -> String {
        await MainActor.run {
            if processCommandValue != "bash start_llama_network.sh" { return processCommandValue }
            if let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("processes.json")),
               let records = try? JSONDecoder().decode([ManagedProcessRecord].self, from: data),
               let record = records.first(where: { $0.pid == pid }) {
                return record.expectedCommand
            }
            return processCommandValue
        }
    }
    func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool {
        await MainActor.run { lastHealthPort = port; lastHealthHost = host; return healthy }
    }
    func tailscaleDiagnostic() async -> TailscaleDiagnostic {
        await MainActor.run { diagnosticCallCount += 1; return diagnostic }
    }
    func discoverModels() async -> [DiscoveredModel] { await MainActor.run { discoveredModels } }
    func hardwareProfile() async -> HardwareProfile { await MainActor.run { hardware } }
}

@MainActor
final class FakeProcessFactory: ProcessMaking {
    var onMake: (() -> Void)?
    var lastProcess: Process?
    func makeProcess() -> Process { onMake?(); let process = Process(); lastProcess = process; return process }
}

struct StubRecommendationProvider: RecommendationProvider {
    let sourceName: String
    let result: Result<[ModelRecommendation], Error>
    func fetch() async throws -> [ModelRecommendation] { try result.get() }
}

/// Records every requested URL and answers from a caller-supplied table so
/// provider behaviour can be asserted without touching the network.
final class StubFetcher: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<HTTPResponse, Error>] = [:]
    private(set) var requestedPaths: [String] = []
    private(set) var requestedURLs: [URL] = []
    private(set) var timeouts: [TimeInterval] = []

    init() {}

    func stub(pathSuffix: String, data: Data = Data(), statusCode: Int = 200) {
        lock.withLock { responses[pathSuffix] = .success(HTTPResponse(data: data, statusCode: statusCode)) }
    }

    func stubFailure(pathSuffix: String) {
        lock.withLock { responses[pathSuffix] = .failure(URLError(.timedOut)) }
    }

    func requestCount(matching pathSuffix: String) -> Int {
        lock.withLock { requestedPaths.filter { $0.hasSuffix(pathSuffix) }.count }
    }

    func fetch(_ url: URL, timeout: TimeInterval) async throws -> HTTPResponse {
        lock.withLock {
            requestedPaths.append(url.path)
            requestedURLs.append(url)
            timeouts.append(timeout)
        }
        let match = lock.withLock { responses.first { url.path.hasSuffix($0.key) }?.value }
        switch match {
        case .success(let response): return response
        case .failure(let error): throw error
        case nil: throw URLError(.badURL)
        }
    }
}
