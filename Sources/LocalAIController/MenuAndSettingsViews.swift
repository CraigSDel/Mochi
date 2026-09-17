import SwiftUI
import AppKit
import ServiceManagement

struct MenuView: View {
    @ObservedObject var manager: ServiceManager
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack {
            BrandMark(size: 24)
            Text("Local AI Controller").font(.headline)
        }
        ForEach(manager.services) { service in
            Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: {
                Label("\(service.definition.name) — \(service.state.displayName)", systemImage: service.state.symbolName)
            }
        }
        Divider()
        Button { attemptStartAll(manager) } label: { Label("Start All", systemImage: "play.fill") }
        Button { Task { await manager.stopAll() } } label: { Label("Stop All", systemImage: "stop.fill") }
        Divider()
        Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: { Label("Open Controller", systemImage: "macwindow") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

@MainActor

struct SettingsView: View {
    @ObservedObject var manager: ServiceManager
    @State private var loginError = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(eyebrow: "Preferences", title: "Settings", subtitle: "Make Local AI Controller available when you need it.", symbol: "gearshape.fill")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { manager.launchAtLogin }, set: updateLogin)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Launch at Login").font(.headline)
                        Text("Open the controller automatically when you sign in to this Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !loginError.isEmpty {
                    Label(loginError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                }
            }
            .appCard()
            Label("Ports, models, and network access are configured on each service screen.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24).frame(width: 520, height: 330)
        .tint(AppTheme.accent)
            .onAppear { manager.launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            manager.launchAtLogin = enabled
        } catch { loginError = error.localizedDescription }
    }
}
