import Foundation
@testable import LocalAIController

@MainActor
final class FakeProbe: SystemProbing {
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
    var diagnostic = TailscaleDiagnostic(status: .direct, peer: "test-peer", detail: "direct", checkedAt: Date())
    var diagnosticCallCount = 0
    init(directory: URL) { supportDirectory = directory }
    func commandPath(_ command: String) -> String? { commands[command] }
    func isPortListening(_ port: Int) -> Bool { portListeningCheck?(port) ?? occupiedPorts.contains(port) }
    func tailscaleIP() -> String? { tailnetIP }
    func wifiIP() -> String? { wifiIPv4 }
    func localNetworkIP() -> String? { lanIP }
    func availableDiskBytes() -> Int64 { diskBytes }
    func scriptURL(named name: String) -> URL? { script }
    func isProcessRunning(_ pid: Int32) -> Bool { processRunningCheck?(pid) ?? processRunning }
    func processCommand(_ pid: Int32) -> String { processCommandValue }
    func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool { lastHealthPort = port; lastHealthHost = host; return healthy }
    func tailscaleDiagnostic() async -> TailscaleDiagnostic { diagnosticCallCount += 1; return diagnostic }
    func discoverModels() -> [DiscoveredModel] { discoveredModels }
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
