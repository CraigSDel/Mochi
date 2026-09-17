import SwiftUI
import AppKit
import ServiceManagement

@main
struct LocalAIControllerApp: App {
    @StateObject private var manager = ServiceManager()
    @StateObject private var recommendations = RecommendationStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Local AI Controller", id: "main") {
            MainView(manager: manager, recommendations: recommendations)
                .frame(minWidth: 760, minHeight: 560)
                .onAppear { appDelegate.manager = manager }
        }
        MenuBarExtra("Local AI", systemImage: menuIcon) {
            MenuView(manager: manager)
        }
        Settings {
            SettingsView(manager: manager)
        }
    }

    private var menuIcon: String {
        manager.services.contains(where: { $0.state == .running }) ? "cpu.fill" : "cpu"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var manager: ServiceManager?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager, manager.hasManagedRunningServices else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Models are still running"
        alert.informativeText = "Keep them running after the controller quits, or stop services started by this app?"
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Stop Services")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .terminateNow
        case .alertSecondButtonReturn:
            Task { @MainActor in await manager.stopAll(); sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        default: return .terminateCancel
        }
    }
}

struct MainView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @State private var selection: ServiceID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Services") {
                    ForEach(manager.services) { service in
                        Label(service.definition.name, systemImage: icon(for: service.state)).tag(service.id)
                    }
                }
                Section("Discover") { Label("Recommendations", systemImage: "sparkles").tag(nil as ServiceID?) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            if let selection, let service = manager.services.first(where: { $0.id == selection }) {
                ServiceDetail(service: service, manager: manager)
            } else {
                RecommendationsView(store: recommendations)
            }
        }
        .toolbar {
            Button("Start All") { promptToStartAll(manager) }
            Button("Stop All") { Task { await manager.stopAll() } }
            Button { Task { await manager.refreshStatuses() } } label: { Image(systemName: "arrow.clockwise") }
        }
        .alert(item: $manager.presentedFailure) { failure in
            Alert(
                title: Text("\(failure.serviceName) failed"),
                message: Text("\(failure.message)\n\n\(failure.guidance)"),
                primaryButton: .default(Text("Reveal Log")) { NSWorkspace.shared.activateFileViewerSelecting([failure.logURL]) },
                secondaryButton: .cancel(Text("Dismiss"))
            )
        }
    }

    private func icon(for state: ServiceState) -> String {
        switch state {
        case .running: "circle.fill"
        case .starting, .stopping: "clock"
        case .failed: "exclamationmark.triangle"
        case .unavailable: "nosign"
        case .external: "link"
        case .stopped: "circle"
        }
    }
}

struct ServiceDetail: View {
    let service: ServiceSnapshot
    @ObservedObject var manager: ServiceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text(service.definition.name).font(.title)
                    Text(service.definition.detail).foregroundStyle(.secondary)
                }
                Spacer()
                Text(service.state.rawValue.capitalized).padding(8).background(.quaternary, in: Capsule())
            }
            Text(service.statusText).foregroundStyle(service.state == .failed ? .red : .secondary)
            if let endpoint = service.endpoint { Text(endpoint).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
            HStack {
                Button("Start") { promptToStart(service.id, manager: manager) }
                    .disabled(!service.definition.supported || [.running, .starting, .external].contains(service.state))
                Button("Stop") { Task { await manager.stop(service.id) } }
                    .disabled(![.running, .starting].contains(service.state) || service.pid == nil)
                Spacer()
                Button("Copy Logs") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(service.logText, forType: .string) }
                Button("Clear") { manager.clearLog(service.id) }
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([manager.logURL(service.id)]) }
            }
            TextEditor(text: .constant(service.logText.isEmpty ? "No log output." : service.logText))
                .font(.system(.caption, design: .monospaced)).border(.separator).disabled(true)
        }.padding()
    }
}

struct RecommendationsView: View {
    @ObservedObject var store: RecommendationStore
    @State private var role: RecommendationRole?
    var filtered: [ModelRecommendation] { role.map { wanted in store.recommendations.filter { $0.role == wanted } } ?? store.recommendations }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Safe model recommendations").font(.title)
                    Text("Read-only advice. This screen never downloads or starts a model.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Now") { Task { await store.refresh() } }.disabled(store.isRefreshing)
            }
            Picker("Role", selection: $role) {
                Text("All roles").tag(nil as RecommendationRole?)
                ForEach(RecommendationRole.allCases, id: \.self) { Text($0.rawValue).tag($0 as RecommendationRole?) }
            }.pickerStyle(.segmented)
            Text(store.status + (store.lastChecked.map { " · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")).font(.caption).foregroundStyle(.secondary)
            List(filtered) { model in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(model.name).font(.headline); Spacer(); Text(model.compatibility.rawValue).foregroundStyle(model.compatibility == .compatible ? .green : .secondary) }
                    Text("\(model.role.rawValue) · \(model.runtime) · \(model.quantization) · \(model.sizeText) · License: \(model.license)").font(.caption)
                    Text(model.rationale).font(.caption).foregroundStyle(.secondary)
                    Text("Source: \(model.source) · Updated: \(model.updatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "unknown")").font(.caption2).foregroundStyle(.tertiary)
                }.padding(.vertical, 4)
            }
        }.padding()
    }
}

struct MenuView: View {
    @ObservedObject var manager: ServiceManager
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ForEach(manager.services) { service in
            Button("\(service.state == .running ? "●" : "○") \(service.definition.name)") { openWindow(id: "main") }
        }
        Divider()
        Button("Start All") { promptToStartAll(manager) }
        Button("Stop All") { Task { await manager.stopAll() } }
        Button("Open Controller") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

@MainActor
private func downloadChoice(title: String) -> Bool? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "Cached Only will never download. Allow Downloads may fetch any configured model that is missing; model downloads can be large."
    alert.addButton(withTitle: "Cached Only")
    alert.addButton(withTitle: "Allow Downloads")
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return false
    case .alertSecondButtonReturn: return true
    default: return nil
    }
}

@MainActor
private func promptToStart(_ id: ServiceID, manager: ServiceManager) {
    guard let allowDownloads = downloadChoice(title: "Start this model service?") else { return }
    Task { await manager.start(id, allowDownloads: allowDownloads) }
}

@MainActor
private func promptToStartAll(_ manager: ServiceManager) {
    guard let allowDownloads = downloadChoice(title: "Start all model services?") else { return }
    Task { await manager.startAll(allowDownloads: allowDownloads) }
}

struct SettingsView: View {
    @ObservedObject var manager: ServiceManager
    @State private var loginError = ""
    var body: some View {
        Form {
            TextField("llama.cpp chat port", value: $manager.chatPort, format: .number)
            Toggle("Launch at Login", isOn: Binding(get: { manager.launchAtLogin }, set: updateLogin))
            if !loginError.isEmpty { Text(loginError).foregroundStyle(.red).font(.caption) }
            Text("Ports 1024–65535 are allowed. Changes apply on the next launch.").font(.caption).foregroundStyle(.secondary)
        }.padding().frame(width: 420)
            .onAppear { manager.launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            manager.launchAtLogin = enabled
        } catch { loginError = error.localizedDescription }
    }
}
