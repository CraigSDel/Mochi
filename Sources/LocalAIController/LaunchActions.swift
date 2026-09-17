import SwiftUI
import AppKit

private func confirmWarnings(_ warnings: [LaunchWarning]) -> Bool {
    guard !warnings.isEmpty else { return true }
    let alert = NSAlert()
    alert.alertStyle = .warning; alert.messageText = "Review launch warnings"
    alert.informativeText = warnings.map { "• \($0.message)" }.joined(separator: "\n")
    alert.addButton(withTitle: "Acknowledge and Start"); alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
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
    let warnings = manager.launchWarnings(for: [id]); guard confirmWarnings(warnings) else { return }
    guard confirmRequiredDownloads(for: [id], manager: manager) else { return }
    Task { await manager.start(id, warningsAcknowledged: !warnings.isEmpty) }
}

@MainActor
func attemptStartAll(_ manager: ServiceManager) {
    let issues = manager.validationIssuesForStartAll(); guard issues.isEmpty else { showConfigurationErrors(issues); return }
    let ids: [ServiceID] = [.ollama, .llamaChat, .autocomplete, .embeddings]
    let warnings = manager.launchWarnings(for: ids); guard confirmWarnings(warnings) else { return }
    guard confirmRequiredDownloads(for: ids, manager: manager) else { return }
    Task { await manager.startAll(warningsAcknowledged: !warnings.isEmpty) }
}

