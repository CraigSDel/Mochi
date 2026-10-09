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

private struct ModelLibraryRow: View {
    let model: DiscoveredModel
    let metadata: ModelMetadata?
    let services: [ServiceSnapshot]
    @ObservedObject var manager: ServiceManager
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAssign: (ServiceID, Bool) -> Void
    @State private var settingsService: ServiceID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: model.runtime == .ollama ? "shippingbox.fill" : "doc.zipper")
                    .font(.title2).foregroundStyle(AppTheme.accent).frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata?.alias ?? model.name).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    var metadata = manager.modelMetadata
                    let current = metadata[model.id] ?? ModelMetadata(alias: model.name, role: model.roleHint, assignedServices: [])
                    metadata[model.id] = ModelMetadata(alias: current.alias, role: current.role, assignedServices: current.assignedServices, isPinned: !current.isPinned)
                    manager.updateModelMetadata(metadata)
                } label: {
                    Image(systemName: metadata?.isPinned == true ? "pin.fill" : "pin")
                }
                .buttonStyle(AppleIconButtonStyle())
                .help(metadata?.isPinned == true ? "Unpin model" : "Pin model")
                Button("Edit", action: onEdit).buttonStyle(AppleSecondaryButtonStyle())
                Button("Delete", role: .destructive, action: onDelete).buttonStyle(AppleDestructiveButtonStyle())
            }
            HStack(spacing: 8) {
                Text("Assign to:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(services.filter(compatible)) { service in
                    HStack(spacing: 5) {
                        Toggle(service.definition.name, isOn: Binding(get: { metadata?.assignedServices.contains(service.id) == true }, set: { onAssign(service.id, $0) }))
                            .toggleStyle(.checkbox).font(.caption)
                        if metadata?.assignedServices.contains(service.id) == true {
                            Button { settingsService = service.id } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(AppleIconButtonStyle()).help("Configure this model assignment")
                        }
                    }
                }
            }
        }
        .appCard(padding: 14)
        .sheet(item: $settingsService) { serviceID in
            let role = serviceID == .ollama ? (metadata?.role ?? model.roleHint) : nil
            ModelAssignmentSettingsSheet(serviceID: serviceID, role: role, manager: manager)
        }
    }

    private var detail: String {
        [model.runtime.title, model.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }, model.roleHint.rawValue, model.supportsVision ? "Vision" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func compatible(_ service: ServiceSnapshot) -> Bool {
        model.runtime == .ollama ? service.id == .ollama : service.id != .ollama
    }

}

private struct ModelAssignmentSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let serviceID: ServiceID
    let role: RecommendationRole?
    @ObservedObject var manager: ServiceManager

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Model assignment settings").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(ApplePrimaryButtonStyle())
            }
            PerformanceTuningEditor(serviceID: serviceID, manager: manager, role: role)
        }
        .padding(24).frame(width: 980, height: 560)
    }
}

private struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @State private var query = ""
    @State private var selected: ModelRecommendation?
    @ObservedObject var downloads: ModelDownloadCoordinator

    init(manager: ServiceManager, recommendations: RecommendationStore, downloads: ModelDownloadCoordinator) {
        self.manager = manager
        self.recommendations = recommendations
        self.downloads = downloads
    }

    private var results: [ModelRecommendation] {
        recommendations.recommendations.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.prefix(30).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: "Library", title: "Add model", subtitle: "Choose a compatible catalog model to download.", symbol: "arrow.down.circle")
            HStack {
                TextField("Search catalog", text: $query).textFieldStyle(.plain).appInputSurface()
                Button { Task { await recommendations.refresh() } } label: { Label("Refresh catalog", systemImage: "arrow.clockwise") }.buttonStyle(AppleSecondaryButtonStyle())
            }
            if results.isEmpty {
                FriendlyEmptyState(symbol: "magnifyingglass", title: "No catalog results", message: "Refresh recommendations or try another search.")
            } else {
                List(results) { model in
                    Button { selected = model } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(model.name).font(.headline); Text("\(model.runtime) · \(model.sizeText) · \(model.role.rawValue)").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); CompatibilityBadge(compatibility: model.compatibility)
                        }
                    }.buttonStyle(.plain)
                }.listStyle(.inset)
            }
            if let selected {
                HStack {
                    Text("Ready to add (selected.name) to the download queue.").font(.caption)
                    Spacer()
                    Button("Queue Download") { downloads.enqueue(selected) }
                        .buttonStyle(ApplePrimaryButtonStyle())
                }
            }
            HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(AppleSecondaryButtonStyle()) }
        }
        .padding(24).frame(width: 700, height: 560)
        .task { if recommendations.recommendations.isEmpty { await recommendations.refresh() } }
    }
}

private struct EditModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: DiscoveredModel
    @ObservedObject var manager: ServiceManager
    @State private var alias: String
    @State private var role: RecommendationRole

    init(model: DiscoveredModel, manager: ServiceManager) {
        self.model = model; self.manager = manager
        let metadata = manager.modelMetadata[model.id]
        _alias = State(initialValue: metadata?.alias ?? model.name)
        _role = State(initialValue: metadata?.role ?? model.roleHint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(eyebrow: "Model", title: "Edit model", subtitle: model.name, symbol: "pencil")
            TextField("Display name", text: $alias).textFieldStyle(.plain).appInputSurface()
            ThemedMenuPicker(choices: RecommendationRole.allCases.map { ($0.rawValue, $0) }, selection: $role)
            HStack { Spacer(); Button("Cancel") { dismiss() }.buttonStyle(AppleSecondaryButtonStyle()); Button("Save") { save() }.buttonStyle(ApplePrimaryButtonStyle()) }
        }.padding(24).frame(width: 440)
    }

    private func save() {
        var metadata = manager.modelMetadata
        metadata[model.id] = ModelMetadata(alias: alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.name : alias, role: role, assignedServices: metadata[model.id]?.assignedServices ?? [], isPinned: metadata[model.id]?.isPinned ?? false)
        manager.updateModelMetadata(metadata); dismiss()
    }
}

private extension ModelRuntime {
    var title: String { self == .ollama ? "Ollama" : "llama.cpp" }
    static var allCases: [ModelRuntime] { [.ollama, .llamaCpp] }
}
