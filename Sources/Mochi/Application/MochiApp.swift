import AppKit
import ServiceManagement
import SwiftUI

@main
struct MochiApp: App {
  @AppStorage("appearance.theme") private var themeRawValue = MochiTheme.pink.rawValue
  @StateObject private var recommendations = RecommendationStore()
  @StateObject private var memoryMonitor = MemoryMonitor()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  init() {
    let rawValue = UserDefaults.standard.string(forKey: "appearance.theme")
      ?? MochiTheme.pink.rawValue
    AppTheme.apply(MochiTheme(rawValue: rawValue) ?? .pink)
  }

  var body: some Scene {
    WindowGroup("Mochi", id: "main") {
      MainView(
        manager: appDelegate.manager, recommendations: recommendations, memoryMonitor: memoryMonitor
      )
      .id(themeRawValue)
      .frame(minWidth: 900, minHeight: 640)
      .tint(AppTheme.accent)
      .onAppear {
        Task {
          await memoryMonitor.start(serviceRoots: { [weak serviceManager = appDelegate.manager] in
            serviceManager?.managedProcessMemoryRoots ?? [:]
          })
        }
      }
    }
    MenuBarExtra("Mochi", systemImage: menuIcon) {
      MenuView(manager: appDelegate.manager)
    }
    Settings {
      SettingsView(manager: appDelegate.manager)
        .id(themeRawValue)
    }
  }

  private var menuIcon: String {
    appDelegate.manager.services.contains(where: { $0.state == .running }) ? "cpu.fill" : "cpu"
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let manager: ServiceManager

  override init() {
    self.manager = ServiceManager()
    super.init()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task { @MainActor in
      await manager.stopAll()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
