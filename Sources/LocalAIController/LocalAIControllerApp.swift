import SwiftUI
import AppKit
import ServiceManagement

@main
struct LocalAIControllerApp: App {
    @StateObject private var manager = ServiceManager()
    @StateObject private var recommendations = RecommendationStore()
    @StateObject private var memoryMonitor = MemoryMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Local AI Controller", id: "main") {
            MainView(manager: manager, recommendations: recommendations, memoryMonitor: memoryMonitor)
                .frame(minWidth: 900, minHeight: 640)
                .tint(AppTheme.accent)
                .onAppear {
                    appDelegate.manager = manager
                    memoryMonitor.start(serviceRoots: { [weak serviceManager = manager] in
                        serviceManager?.managedProcessMemoryRoots ?? [:]
                    })
                }
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
