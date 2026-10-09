import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @ObservedObject var memoryMonitor: MemoryMonitor
    @State private var selection: SidebarDestination = .initial
    @StateObject private var downloads: ModelDownloadCoordinator
    private let fileReveal: any FileRevealClient

    init(manager: ServiceManager, recommendations: RecommendationStore, memoryMonitor: MemoryMonitor, fileReveal: (any FileRevealClient)? = nil) {
        self.manager = manager
        self.recommendations = recommendations
        self.memoryMonitor = memoryMonitor
        self.fileReveal = fileReveal ?? LiveFileRevealClient()
        _downloads = StateObject(wrappedValue: ModelDownloadCoordinator(manager: manager, queueStore: DownloadComposition.queueStore()))
    }

    var body: some View {
        NavigationSplitView { sidebar } detail: { detail }
            .background(AppTheme.pageBackground)
            .toolbar {
                Button {
                    Task { await manager.refreshModelInventory(); await manager.refreshStatuses() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh service status")
            }
            .alert(item: $manager.presentedFailure) { failure in
                Alert(title: Text("\(failure.serviceName) failed"), message: Text("\(failure.message)\n\n\(failure.guidance)"), primaryButton: .default(Text("Reveal Log")) { fileReveal.reveal(failure.logURL) }, secondaryButton: .cancel(Text("Dismiss")))
            }
            .onAppear { manager.updateRecommendationMetadata(recommendations.recommendations) }
            .onReceive(recommendations.$recommendations) { manager.updateRecommendationMetadata($0) }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                HStack(spacing: 11) {
                    BrandMark(size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mochi").font(.headline)
                        Text("Local AI workspace").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section("Workspace") {
                Label("Overview", systemImage: "square.grid.2x2.fill").tag(SidebarDestination.overview)
                Label("Setup guide", systemImage: "wand.and.stars").tag(SidebarDestination.setup)
                Label("Models", systemImage: "shippingbox.fill").tag(SidebarDestination.models)
                Label("Recommendations", systemImage: "sparkles").tag(SidebarDestination.recommendations)
            }
            Section("Settings") {
                Label("Settings", systemImage: "gearshape.fill").tag(SidebarDestination.settings)
            }
            Section("Services") {
                ForEach(manager.services) { service in
                    HStack(spacing: 9) {
                        Image(systemName: service.id.symbolName).frame(width: 18)
                        Text(service.definition.name)
                        Spacer(minLength: 5)
                        Circle().fill(AppTheme.color(for: service.state.tone)).frame(width: 7, height: 7).accessibilityLabel(service.state.displayName)
                    }
                    .tag(SidebarDestination.service(service.id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .overview:
            OverviewView(manager: manager, memoryMonitor: memoryMonitor, selection: $selection)
        case .setup:
            SetupGuideView(manager: manager)
        case .models:
            ModelsView(manager: manager, recommendations: recommendations, downloads: downloads)
        case .recommendations:
            RecommendationsView(store: recommendations, manager: manager, downloads: downloads, guidance: manager.performanceGuidance())
        case .settings:
            MainWindowSettingsView(manager: manager)
        case .service(let serviceID):
            if let service = manager.services.first(where: { $0.id == serviceID }) {
                ServiceDetail(service: service, manager: manager, recommendations: recommendations, fileReveal: fileReveal) { selection = .models }
            }
        }
    }
}
