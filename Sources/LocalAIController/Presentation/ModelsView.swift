import SwiftUI

struct ModelsView: View {
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @State private var search = ""
    @State private var runtime: ModelRuntime?
    @State private var showingAdd = false
    @State private var editing: DiscoveredModel?
    @State private var deleting: DiscoveredModel?
    @State private var message: String?
    @ObservedObject var downloads: ModelDownloadCoordinator

    private var models: [DiscoveredModel] {
        let filtered = manager.installedModels.filter { model in
            (runtime == nil || model.runtime == runtime) &&
            (search.isEmpty || model.name.localizedCaseInsensitiveContains(search) || model.repository?.localizedCaseInsensitiveContains(search) == true)
        }
        return filtered.sorted { lhs, rhs in
            let leftPinned = manager.modelMetadata[lhs.id]?.isPinned == true
            let rightPinned = manager.modelMetadata[rhs.id]?.isPinned == true
            if leftPinned != rightPinned { return leftPinned }
            if lhs.runtime != rhs.runtime { return lhs.runtime.rawValue < rhs.runtime.rawValue }
            let leftName = manager.modelMetadata[lhs.id]?.alias ?? lhs.name
            let rightName = manager.modelMetadata[rhs.id]?.alias ?? rhs.name
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PageHeader(eyebrow: "Library", title: "Models", subtitle: "Manage downloaded models and assign them to services.", symbol: "shippingbox.fill")
                    Spacer()
                    Button { showingAdd = true } label: { Label("Add Model", systemImage: "plus") }
                        .buttonStyle(ApplePrimaryButtonStyle())
                    Button { Task { await manager.refreshModelInventory() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(AppleSecondaryButtonStyle())
                }
                HStack(spacing: 10) {
                    TextField("Search downloaded models", text: $search)
                        .textFieldStyle(.plain).appInputSurface()
                    ThemedMenuPicker(choices: [("All runtimes", Optional<ModelRuntime>.none)] + ModelRuntime.allCases.map { ($0.title, Optional($0)) }, selection: $runtime)
                        .frame(width: 190)
                }
                .appCard(padding: 12)
                DownloadManagerSection(downloads: downloads)
                if models.isEmpty {
                    FriendlyEmptyState(symbol: "shippingbox", title: "No downloaded models", message: "Add a model from the catalog or install one with its runtime, then refresh this library.")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(models) { model in
                            ModelLibraryRow(model: model, metadata: manager.modelMetadata[model.id], services: manager.services, manager: manager) {
                                editing = model
                            } onDelete: {
                                deleting = model
                            } onAssign: { serviceID, assigned in
                                manager.assignModel(model, to: serviceID, assigned: assigned)
                            }
                        }
                    }
                }
                if let message {
                    Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 32)
        }
        .background(AppTheme.pageBackground)
        .sheet(isPresented: $showingAdd) { AddModelSheet(manager: manager, recommendations: recommendations, downloads: downloads) }
        .sheet(item: $editing) { model in EditModelSheet(model: model, manager: manager) }
        .confirmationDialog("Delete \(deleting?.name ?? "model")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Model", role: .destructive) {
                guard let model = deleting else { return }
                deleting = nil
                Task {
                    do { try await manager.deleteModel(model) }
                    catch { message = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("This removes the local model files. Services using it must be stopped first.")
        }
    }
}
