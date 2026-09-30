import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @ObservedObject var memoryMonitor: MemoryMonitor
    @State private var selection: SidebarDestination = .initial

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    HStack(spacing: 11) {
                        BrandMark(size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Local AI").font(.headline)
                            Text("Controller").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section("Workspace") {
                    Label("Overview", systemImage: "square.grid.2x2.fill")
                        .tag(SidebarDestination.overview)
                }
                Section("Services") {
                    ForEach(manager.services) { service in
                        HStack(spacing: 9) {
                            Image(systemName: service.id.symbolName).frame(width: 18)
                            Text(service.definition.name)
                            Spacer(minLength: 5)
                            Circle().fill(AppTheme.color(for: service.state.tone)).frame(width: 7, height: 7)
                                .accessibilityLabel(service.state.displayName)
                        }.tag(SidebarDestination.service(service.id))
                    }
                }
                Section("Discover") {
                    Label("Recommendations", systemImage: "sparkles")
                        .tag(SidebarDestination.recommendations)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            switch selection {
            case .overview:
                OverviewView(manager: manager, recommendations: recommendations, memoryMonitor: memoryMonitor, selection: $selection)
            case .service(let serviceID):
                if let service = manager.services.first(where: { $0.id == serviceID }) {
                    ServiceDetail(service: service, manager: manager, recommendations: recommendations)
                }
            case .recommendations:
                RecommendationsView(store: recommendations)
            }
        }
        .background(AppTheme.pageBackground)
        .toolbar {
            Button {
                manager.refreshModelInventory()
                Task { await manager.refreshStatuses() }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh service status")
        }
        .alert(item: $manager.presentedFailure) { failure in
            Alert(
                title: Text("\(failure.serviceName) failed"),
                message: Text("\(failure.message)\n\n\(failure.guidance)"),
                primaryButton: .default(Text("Reveal Log")) { NSWorkspace.shared.activateFileViewerSelecting([failure.logURL]) },
                secondaryButton: .cancel(Text("Dismiss"))
            )
        }
        .onAppear { manager.updateRecommendationMetadata(recommendations.recommendations) }
        .onReceive(recommendations.$recommendations) { manager.updateRecommendationMetadata($0) }
    }

}

struct OverviewView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @ObservedObject var memoryMonitor: MemoryMonitor
    @Binding var selection: SidebarDestination

    private var runningCount: Int { manager.services.filter { $0.state == .running }.count }
    private var activeCount: Int { manager.services.filter { [.running, .starting, .stopping].contains($0.state) }.count }
    private var canStartAll: Bool {
        manager.services.contains { $0.state.canStart && $0.definition.supported } && manager.validationIssuesForStartAll().isEmpty
    }
    private var canStopAll: Bool { manager.services.contains { $0.state.canStop && $0.pid != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    PageHeader(
                        eyebrow: "Control center",
                        title: "Your local AI stack",
                        subtitle: runningCount == 0 ? "Everything is quiet and ready when you are." : "\(runningCount) of \(manager.services.count) services are healthy.",
                        symbol: "cpu.fill"
                    )
                    Spacer()
                    HStack(spacing: 9) {
                        Button("Stop All", role: .destructive) { Task { await manager.stopAll() } }
                            .buttonStyle(AppleDestructiveButtonStyle())
                            .disabled(!canStopAll)
                        Button("Start All") { attemptStartAll(manager) }
                            .buttonStyle(ApplePrimaryButtonStyle())
                            .disabled(!canStartAll)
                    }
                }

                HStack(spacing: 12) {
                    OverviewMetric(title: "Running", value: "\(runningCount)", symbol: "checkmark.circle.fill", tone: .success)
                    OverviewMetric(title: "Active", value: "\(activeCount)", symbol: "bolt.fill", tone: .accent)
                    OverviewMetric(title: "Available", value: "\(manager.services.filter(\.definition.supported).count)", symbol: "shippingbox.fill", tone: .neutral)
                }

                MemoryDashboardView(monitor: memoryMonitor)

                localNetworkCard
                tailscaleDiagnosticCard

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading("Services", subtitle: "Start, stop, and inspect each local runtime.", symbol: "server.rack")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(manager.services) { service in
                            OverviewServiceCard(service: service, manager: manager) { selection = .service(service.id) }
                        }
                    }
                }

                Button { selection = .recommendations } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.title2.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Discover compatible models").font(.headline).foregroundStyle(.primary)
                            Text(recommendations.recommendations.isEmpty ? "Browse safe, read-only recommendations." : "\(recommendations.recommendations.count) recommendations available")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appCard(padding: 15)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
        }
        .background(AppTheme.pageBackground)
    }

    private var tailscaleDiagnosticCard: some View {
        let diagnostic = manager.latestTailscaleDiagnostic
        return HStack(spacing: 14) {
            Image(systemName: diagnostic?.symbolName ?? "network")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.color(for: diagnostic?.tone ?? .neutral))
                .frame(width: 42, height: 42)
                .background(AppTheme.color(for: diagnostic?.tone ?? .neutral).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(diagnostic?.title ?? "Tailscale connectivity").font(.headline)
                Text(diagnostic.map { [$0.peer.map { "Peer: \($0)." }, $0.guidance].compactMap { $0 }.joined(separator: " ") } ?? "Test an online peer to detect direct, relayed, or possibly blocked connectivity.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(manager.isTestingTailscale ? "Testing…" : "Test Tailscale") { Task { await manager.testTailscale() } }
                .buttonStyle(AppleSecondaryButtonStyle())
                .disabled(manager.isTestingTailscale)
        }
        .appCard()
    }

    private var localNetworkCard: some View {
        let address = manager.localNetworkIP()
        return HStack(spacing: 14) {
            Image(systemName: "wifi")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Local network address").font(.headline)
                Text(address ?? "No local network IPv4 address detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if let address {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                } label: {
                    Label("Copy address", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(AppleIconButtonStyle())
                .help("Copy local network address")
            }
        }
        .appCard()
    }
}

private struct OverviewMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold)).foregroundStyle(AppTheme.color(for: tone))
                .frame(width: 36, height: 36)
                .background(AppTheme.color(for: tone).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title2.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: 14)
    }
}

private struct OverviewServiceCard: View {
    let service: ServiceSnapshot
    @ObservedObject var manager: ServiceManager
    let open: () -> Void

    private var canStart: Bool { service.state.canStart && service.definition.supported && manager.validationIssues(for: service.id).isEmpty }
    private var canStop: Bool { service.state.canStop && service.pid != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: service.id.symbolName)
                    .font(.title2.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                StatusBadge(state: service.state)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(service.definition.name).font(.headline)
                Text(service.definition.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Label(service.definition.runtime, systemImage: "gearshape.2")
                Spacer()
                if let endpoint = service.endpoint {
                    Text(endpoint).lineLimit(1).textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(endpoint, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(AppleIconButtonStyle()).help("Copy endpoint")
                } else {
                    Text("Port \(manager.configuration(for: service.id).port)").lineLimit(1)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Open", action: open)
                    .buttonStyle(AppleSecondaryButtonStyle())
                Spacer()
                if canStop {
                    Button("Stop", role: .destructive) { Task { await manager.stop(service.id) } }
                        .buttonStyle(AppleDestructiveButtonStyle())
                } else {
                    Button("Start") { attemptStart(service.id, manager: manager) }
                        .buttonStyle(ApplePrimaryButtonStyle()).disabled(!canStart)
                }
            }
        }
        .appCard()
    }
}
