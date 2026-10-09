import AppKit
import SwiftUI

struct MenuView: View {
  @ObservedObject var manager: ServiceManager
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    HStack {
      BrandMark(size: 24)
      Text("Mochi").font(.headline)
    }
    ForEach(manager.services) { service in
      Button {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
      } label: {
        Label(
          "\(service.definition.name) — \(service.state.displayName)",
          systemImage: service.state.symbolName)
      }
    }
    Divider()
    Button {
      attemptStartAll(manager)
    } label: {
      Label("Start All", systemImage: "play.fill")
    }
    Button {
      Task { await manager.stopAll() }
    } label: {
      Label("Stop All", systemImage: "stop.fill")
    }
    Divider()
    Button {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    } label: {
      Label("Open Mochi", systemImage: "macwindow")
    }
    Divider()
    Button("Quit") { NSApp.terminate(nil) }
  }
}

@MainActor
struct SettingsView: View {
  @ObservedObject var manager: ServiceManager

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      PageHeader(
        eyebrow: "Preferences", title: "Settings",
        subtitle: "Make Mochi available when you need it.", symbol: "gearshape.fill")
      ThemeSettingsSection()
      LaunchAtLoginSection(manager: manager)
      Label(
        "Ports, models, and network access are configured on each service screen.",
        systemImage: "info.circle"
      )
      .font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
    .padding(24).frame(width: 520, height: 420).tint(AppTheme.accent)
  }
}
