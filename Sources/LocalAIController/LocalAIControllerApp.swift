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
            Button("Start All") { attemptStartAll(manager) }
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
        ScrollView {
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
            ServiceConfigurationEditor(serviceID: service.id, manager: manager)
            HStack {
                Button("Start") { attemptStart(service.id, manager: manager) }
                    .disabled(!service.definition.supported || [.running, .starting, .external].contains(service.state) || !manager.validationIssues(for: service.id).isEmpty)
                Button("Stop") { Task { await manager.stop(service.id) } }
                    .disabled(![.running, .starting].contains(service.state) || service.pid == nil)
                Spacer()
                Button("Copy Logs") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(service.logText, forType: .string) }
                Button("Clear") { manager.clearLog(service.id) }
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([manager.logURL(service.id)]) }
            }
            TextEditor(text: .constant(service.logText.isEmpty ? "No log output." : service.logText))
                .font(.system(.caption, design: .monospaced)).border(.separator).disabled(true).frame(minHeight: 180)
        }.padding()
        }
    }
}

struct ServiceConfigurationEditor: View {
    let serviceID: ServiceID
    @ObservedObject var manager: ServiceManager
    @State private var advanced = false

    private var configuration: ServiceLaunchConfiguration { manager.configuration(for: serviceID) }
    private var locked: Bool { manager.isConfigurationLocked(serviceID) }

    var body: some View {
        GroupBox("Launch configuration") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Port", value: commonBinding(\.port), format: .number).frame(maxWidth: 180)
                    Picker("Bind", selection: commonBinding(\.bindMode)) { ForEach(BindMode.allCases) { Text($0.title).tag($0) } }.frame(maxWidth: 260)
                    Picker("Download", selection: commonBinding(\.downloadPolicy)) { ForEach(DownloadPolicy.allCases) { Text($0.title).tag($0) } }.frame(maxWidth: 260)
                }
                if configuration.llama != nil { llamaFields } else if configuration.ollama != nil { ollamaFields }
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    if configuration.llama != nil { llamaAdvanced } else if configuration.ollama != nil { ollamaAdvanced }
                }
                let issues = manager.validationIssues(for: serviceID)
                ForEach(issues) { Text($0.message).font(.caption).foregroundStyle(.red) }
                HStack {
                    if locked { Label("Stop the service to edit its launch configuration.", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Reset to Defaults") { manager.resetConfiguration(serviceID) }.disabled(locked || configuration == .defaultValue(for: serviceID))
                }
            }.padding(8).disabled(locked)
        }
    }

    private var llamaFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Hugging Face repository", text: llamaBinding(\.repository))
            TextField("GGUF filename", text: llamaBinding(\.filename))
            TextField("Model alias", text: llamaBinding(\.alias))
        }
    }
    private var llamaAdvanced: some View {
        HStack {
            TextField("Context size", value: llamaBinding(\.contextSize), format: .number)
            TextField("GPU layers", value: llamaBinding(\.gpuLayers), format: .number)
        }.padding(.top, 8)
    }
    private var ollamaFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Chat model", text: ollamaBinding(\.chatModel))
            TextField("Autocomplete model", text: ollamaBinding(\.autocompleteModel))
            TextField("Embedding model", text: ollamaBinding(\.embeddingModel))
        }
    }
    private var ollamaAdvanced: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Flash attention", isOn: ollamaBinding(\.flashAttention))
            TextField("KV cache type", text: ollamaBinding(\.kvCacheType))
            HStack {
                TextField("Context length", value: ollamaBinding(\.contextLength), format: .number)
                TextField("Parallel requests", value: ollamaBinding(\.parallelRequests), format: .number)
                TextField("Max loaded models", value: ollamaBinding(\.maxLoadedModels), format: .number)
            }
        }.padding(.top, 8)
    }
    private func commonBinding<Value>(_ keyPath: WritableKeyPath<ServiceLaunchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in var copy = configuration; copy[keyPath: keyPath] = value; manager.updateConfiguration(copy, for: serviceID) })
    }
    private func llamaBinding<Value>(_ keyPath: WritableKeyPath<LlamaLaunchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration.llama![keyPath: keyPath] }, set: { value in var copy = configuration; copy.llama![keyPath: keyPath] = value; manager.updateConfiguration(copy, for: serviceID) })
    }
    private func ollamaBinding<Value>(_ keyPath: WritableKeyPath<OllamaLaunchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration.ollama![keyPath: keyPath] }, set: { value in var copy = configuration; copy.ollama![keyPath: keyPath] = value; manager.updateConfiguration(copy, for: serviceID) })
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
        Button("Start All") { attemptStartAll(manager) }
        Button("Stop All") { Task { await manager.stopAll() } }
        Button("Open Controller") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

@MainActor
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
private func attemptStart(_ id: ServiceID, manager: ServiceManager) {
    let issues = manager.validationIssues(for: id); guard issues.isEmpty else { showConfigurationErrors(issues); return }
    let warnings = manager.launchWarnings(for: [id]); guard confirmWarnings(warnings) else { return }
    Task { await manager.start(id, warningsAcknowledged: !warnings.isEmpty) }
}

@MainActor
private func attemptStartAll(_ manager: ServiceManager) {
    let issues = manager.validationIssuesForStartAll(); guard issues.isEmpty else { showConfigurationErrors(issues); return }
    let warnings = manager.launchWarnings(for: [.ollama, .llamaChat, .autocomplete, .embeddings]); guard confirmWarnings(warnings) else { return }
    Task { await manager.startAll(warningsAcknowledged: !warnings.isEmpty) }
}

struct SettingsView: View {
    @ObservedObject var manager: ServiceManager
    @State private var loginError = ""
    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: Binding(get: { manager.launchAtLogin }, set: updateLogin))
            if !loginError.isEmpty { Text(loginError).foregroundStyle(.red).font(.caption) }
            Text("Configure ports, models, and networking on each service screen.").font(.caption).foregroundStyle(.secondary)
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
