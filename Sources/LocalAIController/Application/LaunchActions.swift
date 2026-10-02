import SwiftUI
import AppKit

enum LaunchWarningDecision: Equatable {
    case configured, localhost, lan, cancel
    var shouldStart: Bool { self != .cancel }
    var bindModeOverride: BindMode? { switch self { case .localhost: .localhost; case .lan: .lan; case .configured, .cancel: nil } }
}

enum StartAllNetworkDecision: Equatable {
    case tailscale, localhost, cancel

    var shouldStart: Bool { self != .cancel }
    var bindMode: BindMode? {
        switch self {
        case .tailscale: .tailscale
        case .localhost: .localhost
        case .cancel: nil
        }
    }
}

@MainActor
private func chooseStartAllNetworkMode() -> StartAllNetworkDecision {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Choose Start All network"
    alert.informativeText = "Choose where the llama.cpp services should listen for this launch. Your saved per-service Network settings will not change."
    alert.addButton(withTitle: "Start on Tailscale")
    alert.addButton(withTitle: "Start Locally")
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return .tailscale
    case .alertSecondButtonReturn: return .localhost
    default: return .cancel
    }
}

@MainActor
private func confirmWarnings(_ warnings: [LaunchWarning], offersLocalFallback: Bool, offersWiFiFallback: Bool) -> LaunchWarningDecision {
    guard !warnings.isEmpty else { return .configured }
    let alert = NSAlert()
    alert.alertStyle = .warning; alert.messageText = "Review launch warnings"
    let wifiNotice = offersWiFiFallback ? "\n\nStart on Wi-Fi exposes these unauthenticated APIs to devices on the local network." : ""
    alert.informativeText = warnings.map { "• \($0.message)" }.joined(separator: "\n") + wifiNotice
    alert.addButton(withTitle: offersLocalFallback ? "Start Anyway" : "Acknowledge and Start")
    if offersLocalFallback { alert.addButton(withTitle: "Start Locally") }
    if offersWiFiFallback { alert.addButton(withTitle: "Start on Wi-Fi") }
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return .configured
    case .alertSecondButtonReturn where offersLocalFallback: return .localhost
    case .alertThirdButtonReturn where offersWiFiFallback: return .lan
    default: return .cancel
    }
}

@MainActor
private func showConfigurationErrors(_ issues: [ConfigurationIssue]) {
    let alert = NSAlert(); alert.alertStyle = .critical; alert.messageText = "Invalid launch configuration"
    alert.informativeText = issues.map { "• \($0.message)" }.joined(separator: "\n"); alert.runModal()
}

@MainActor
private func confirmRequiredDownloads(for ids: [ServiceID], manager: ServiceManager) -> Bool {
    let missing = ids.flatMap { id in manager.modelsRequiringDownload(for: id).map { "\(id.rawValue): \($0)" } }
    guard !missing.isEmpty else { return true }
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = missing.count == 1 ? "Download this model?" : "Download required models?"
    alert.informativeText = "The following selections are not installed:\n\n" + missing.map { "• \($0)" }.joined(separator: "\n") + "\n\nAllow downloads and continue?"
    alert.addButton(withTitle: "Allow Downloads & Start")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    manager.enableDownloads(for: ids.filter { !manager.modelsRequiringDownload(for: $0).isEmpty })
    return true
}

@MainActor
func attemptStart(_ id: ServiceID, manager: ServiceManager) {
    let issues = manager.validationIssues(for: id); guard issues.isEmpty else { showConfigurationErrors(issues); return }
    Task {
        var warnings = manager.launchWarnings(for: [id])
        let networkWarning = await manager.tailscaleLaunchWarning(for: [id])
        if let networkWarning { warnings.append(networkWarning) }
        let offersWiFi = networkWarning != nil && manager.wifiIP() != nil
        let decision = confirmWarnings(warnings, offersLocalFallback: networkWarning != nil, offersWiFiFallback: offersWiFi)
        guard decision.shouldStart else { return }
        guard confirmRequiredDownloads(for: [id], manager: manager) else { return }
        await manager.start(id, warningsAcknowledged: !warnings.isEmpty, bindModeOverride: decision.bindModeOverride)
    }
}

@MainActor
func attemptStartAll(_ manager: ServiceManager) {
    let issues = manager.validationIssuesForStartAll(); guard issues.isEmpty else { showConfigurationErrors(issues); return }
    let ids = ServiceManager.startAllServiceIDs
    Task {
        let networkDecision = chooseStartAllNetworkMode()
        guard networkDecision.shouldStart, let selectedMode = networkDecision.bindMode else { return }
        var warnings = manager.launchWarnings(for: ids, bindModeOverride: selectedMode)
        let networkWarning = await manager.tailscaleLaunchWarning(for: ids, bindModeOverride: selectedMode)
        if let networkWarning { warnings.append(networkWarning) }
        let offersWiFi = networkWarning != nil && manager.wifiIP() != nil
        let decision = confirmWarnings(warnings, offersLocalFallback: networkWarning != nil, offersWiFiFallback: offersWiFi)
        guard decision.shouldStart else { return }
        guard confirmRequiredDownloads(for: ids, manager: manager) else { return }
        await manager.startAll(
            warningsAcknowledged: !warnings.isEmpty,
            bindModeOverride: decision.bindModeOverride ?? selectedMode
        )
    }
}
