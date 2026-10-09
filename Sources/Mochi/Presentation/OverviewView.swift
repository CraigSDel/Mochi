import SwiftUI

struct OverviewView: View {
  @ObservedObject var manager: ServiceManager
  @ObservedObject var memoryMonitor: MemoryMonitor
  @Binding var selection: SidebarDestination

  private var runningCount: Int { manager.services.filter { $0.state == .running }.count }
  private var activeCount: Int {
    manager.services.filter { [.running, .starting, .stopping].contains($0.state) }.count
  }
  private var canStartAll: Bool {
    manager.services.contains { $0.state.canStart && $0.definition.supported }
      && manager.validationIssuesForStartAll().isEmpty
  }
  private var canStopAll: Bool { manager.services.contains { $0.state.canStop && $0.pid != nil } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .center) {
          PageHeader(
            eyebrow: "Mochi workspace", title: "Your cozy AI corner",
            subtitle: runningCount == 0
              ? "Everything is quiet and ready when you are."
              : "\(runningCount) of \(manager.services.count) services are healthy.",
            symbol: "cpu.fill")
          Spacer()
          HStack(spacing: 9) {
            Button("Stop All", role: .destructive) { Task { await manager.stopAll() } }
              .buttonStyle(AppleDestructiveButtonStyle()).disabled(!canStopAll)
            Button("Start All") { attemptStartAll(manager) }
              .buttonStyle(ApplePrimaryButtonStyle()).disabled(!canStartAll)
          }
        }
        HStack(spacing: 12) {
          OverviewMetric(
            title: "Running", value: "\(runningCount)", symbol: "checkmark.circle.fill",
            tone: .success)
          OverviewMetric(
            title: "Active", value: "\(activeCount)", symbol: "bolt.fill", tone: .accent)
          OverviewMetric(
            title: "Available", value: "\(manager.services.filter(\.definition.supported).count)",
            symbol: "shippingbox.fill", tone: .neutral)
        }
        MemoryDashboardView(monitor: memoryMonitor)
        VStack(alignment: .leading, spacing: 12) {
          SectionHeading(
            "Services", subtitle: "Start, stop, and inspect each local runtime.",
            symbol: "server.rack")
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            ForEach(manager.services) { service in
              OverviewServiceCard(service: service, manager: manager) {
                selection = .service(service.id)
              }
            }
          }
        }
      }
      .padding(.horizontal, 28).padding(.vertical, 26)
    }
    .background(AppTheme.mochiBackdrop)
  }
}
