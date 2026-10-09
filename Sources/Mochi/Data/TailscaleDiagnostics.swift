import Foundation

enum TailscaleDiagnosticStatus: String, Equatable, Sendable {
    case checking, direct, relayed, unreachable, noOnlinePeers, disconnected, missingCLI, commandFailure
}

struct TailscaleDiagnostic: Equatable, Sendable {
    let status: TailscaleDiagnosticStatus
    let peer: String?
    let detail: String
    let checkedAt: Date

    var title: String {
        switch status {
        case .checking: "Testing Tailscale…"
        case .direct: "Tailscale is working"
        case .relayed: "Tailscale is relayed"
        case .unreachable: "Tailscale peer is unreachable"
        case .noOnlinePeers: "No online Tailscale peers"
        case .disconnected: "Tailscale is disconnected"
        case .missingCLI: "Tailscale is not installed"
        case .commandFailure: "Tailscale test failed"
        }
    }

    var guidance: String {
        switch status {
        case .checking: "Waiting for the connectivity test to finish."
        case .direct: "A direct peer-to-peer path is available."
        case .relayed: "Traffic works through a relay, but direct UDP connectivity may be blocked."
        case .unreachable: "Peer traffic may be blocked, denied by tailnet policy, or the selected peer may have gone offline."
        case .noOnlinePeers: "Tailscale is connected, but no online peer is available to verify traffic."
        case .disconnected: "Connect Tailscale, then run the test again."
        case .missingCLI: "Install Tailscale before using Tailscale-bound services."
        case .commandFailure: "Review the diagnostic detail and verify the Tailscale daemon is responding."
        }
    }

    var symbolName: String {
        switch status {
        case .checking: "hourglass"
        case .direct: "checkmark.circle.fill"
        case .relayed, .noOnlinePeers: "exclamationmark.triangle.fill"
        case .unreachable, .disconnected, .missingCLI, .commandFailure: "xmark.octagon.fill"
        }
    }

    var tone: StatusTone {
        switch status {
        case .direct: .success
        case .checking, .relayed, .noOnlinePeers: .warning
        case .unreachable, .disconnected, .missingCLI, .commandFailure: .danger
        }
    }

    var launchWarning: String? { status == .direct ? nil : "\(title). \(guidance)" }
}

struct TailscalePeer: Equatable, Sendable {
    let name: String
    let target: String
}

enum TailscaleStatusParser {
    private struct Document: Decodable {
        let backendState: String?
        let peers: [String: Peer]?
        enum CodingKeys: String, CodingKey { case backendState = "BackendState"; case peers = "Peer" }
    }

    private struct Peer: Decodable {
        let hostName: String?
        let dnsName: String?
        let addresses: [String]?
        let online: Bool?
        enum CodingKeys: String, CodingKey { case hostName = "HostName"; case dnsName = "DNSName"; case addresses = "TailscaleIPs"; case online = "Online" }
    }

    static func connectedAndPeer(from data: Data) throws -> (connected: Bool, peer: TailscalePeer?) {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.backendState?.lowercased() == "running" else { return (false, nil) }
        let candidates = (document.peers ?? [:]).values.compactMap { peer -> TailscalePeer? in
            guard peer.online == true else { return nil }
            let dns = peer.dnsName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let name = [peer.hostName, dns].compactMap { $0 }.first { !$0.isEmpty } ?? "Unknown peer"
            let target = peer.addresses?.first(where: { $0.contains(".") }) ?? dns ?? peer.hostName
            return target.map { TailscalePeer(name: name, target: $0) }
        }
        return (true, candidates.sorted { ($0.name.lowercased(), $0.target) < ($1.name.lowercased(), $1.target) }.first)
    }

    static func pingStatus(output: String, exitCode: Int32) -> TailscaleDiagnosticStatus {
        guard exitCode == 0 else { return .unreachable }
        let lower = output.lowercased()
        return lower.contains("derp") || lower.contains("peer-relay") || lower.contains("relay") ? .relayed : .direct
    }
}

private struct DiagnosticCommandResult: Sendable {
    let output: String
    let status: Int32
}

extension LiveSystemProbe {
    func tailscaleDiagnostic() async -> TailscaleDiagnostic {
        let now = Date()
        guard let executable = await commandPath("tailscale") else { return .init(status: .missingCLI, peer: nil, detail: "The tailscale command was not found.", checkedAt: now) }
        guard let status = await Self.runDiagnosticCommand(executable, ["status", "--json"]) else { return .init(status: .commandFailure, peer: nil, detail: "Could not run tailscale status --json.", checkedAt: now) }
        guard status.status == 0 else { return .init(status: .commandFailure, peer: nil, detail: status.output, checkedAt: now) }
        let parsed: (connected: Bool, peer: TailscalePeer?)
        do { parsed = try TailscaleStatusParser.connectedAndPeer(from: Data(status.output.utf8)) }
        catch { return .init(status: .commandFailure, peer: nil, detail: "Tailscale returned an unreadable status response.", checkedAt: now) }
        guard parsed.connected else { return .init(status: .disconnected, peer: nil, detail: "The Tailscale backend is not running.", checkedAt: now) }
        guard let peer = parsed.peer else { return .init(status: .noOnlinePeers, peer: nil, detail: "No online peer was reported by Tailscale.", checkedAt: now) }
        guard let ping = await Self.runDiagnosticCommand(executable, ["ping", "--c", "1", "--timeout=3s", "--until-direct=false", peer.target]) else { return .init(status: .commandFailure, peer: peer.name, detail: "Could not run tailscale ping.", checkedAt: now) }
        let result = TailscaleStatusParser.pingStatus(output: ping.output, exitCode: ping.status)
        return .init(status: result, peer: peer.name, detail: ping.output.isEmpty ? "tailscale ping returned no output." : ping.output, checkedAt: now)
    }

    private nonisolated static func runDiagnosticCommand(_ executable: String, _ arguments: [String]) async -> DiagnosticCommandResult? {
        await Task.detached(priority: .utility) {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = pipe; process.standardError = pipe
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .init(output: output, status: process.terminationStatus)
        }.value
    }
}
