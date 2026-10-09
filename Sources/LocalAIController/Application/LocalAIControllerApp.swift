import SwiftUI
import AppKit
import ServiceManagement

@main
struct LocalAIControllerApp: App {
    @StateObject private var recommendations = RecommendationStore()
    @StateObject private var memoryMonitor = MemoryMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Local AI Controller", id: "main") {
            MainView(manager: appDelegate.manager, recommendations: recommendations, memoryMonitor: memoryMonitor)
                .frame(minWidth: 900, minHeight: 640)
                .tint(AppTheme.accent)
                .onAppear {
                    Task { await memoryMonitor.start(serviceRoots: { [weak serviceManager = appDelegate.manager] in
                        serviceManager?.managedProcessMemoryRoots ?? [:]
                    }) }
                }
        }
        MenuBarExtra("Local AI", systemImage: menuIcon) {
            MenuView(manager: appDelegate.manager)
        }
        Settings {
            SettingsView(manager: appDelegate.manager)
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
