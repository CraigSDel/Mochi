import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @ObservedObject var memoryMonitor: MemoryMonitor
    @State private var selection: SidebarDestination = .initial
    @StateObject private var downloads: ModelDownloadCoordinator
    private let fileReveal: any FileRevealClient

    init(
        manager: ServiceManager,
        recommendations: RecommendationStore,
        memoryMonitor: MemoryMonitor,
        fileReveal: (any FileRevealClient)? = nil
    ) {
        self.manager = manager
        self.recommendations = recommendations
        self.memoryMonitor = memoryMonitor
        self.fileReveal = fileReveal ?? LiveFileRevealClient()
        _downloads = StateObject(wrappedValue: ModelDownloadCoordinator(
            manager: manager,
            queueStore: DownloadComposition.queueStore()
        ))
    }

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
                    Label("Models", systemImage: "shippingbox.fill")
                        .tag(SidebarDestination.models)
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
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            switch selection {
            case .overview:
                OverviewView(manager: manager, recommendations: recommendations, memoryMonitor: memoryMonitor, selection: $selection)
            case .models:
                ModelsView(manager: manager, recommendations: recommendations, downloads: downloads)
            case .service(let serviceID):
                if let service = manager.services.first(where: { $0.id == serviceID }) {
                    ServiceDetail(service: service, manager: manager, recommendations: recommendations, fileReveal: fileReveal) { selection = .models }
                }
            case .recommendations:
                RecommendationsView(store: recommendations, downloads: downloads, guidance: manager.performanceGuidance())
            }
        }
        .background(AppTheme.pageBackground)
        .toolbar {
            Button {
                Task {
                    await manager.refreshModelInventory()
                    await manager.refreshStatuses()
                }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh service status")
        }
        .alert(item: $manager.presentedFailure) { failure in
            Alert(
                title: Text("\(failure.serviceName) failed"),
                message: Text("\(failure.message)\n\n\(failure.guidance)"),
                primaryButton: .default(Text("Reveal Log")) { fileReveal.reveal(failure.logURL) },
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
    @State private var localNetworkAddress: String?

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
        let address = localNetworkAddress
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
        .task { localNetworkAddress = await manager.localNetworkIP() }
    }
}
