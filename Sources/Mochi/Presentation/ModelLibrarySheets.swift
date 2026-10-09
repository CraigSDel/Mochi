import SwiftUI

struct ModelLibraryRow: View {
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
        Image(systemName: "doc.zipper")
          .font(.title2).foregroundStyle(AppTheme.accent).frame(width: 38, height: 38)
        VStack(alignment: .leading, spacing: 3) {
          Text(metadata?.alias ?? model.name).font(.headline)
          Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          var metadata = manager.modelMetadata
          let current =
            metadata[model.id]
            ?? ModelMetadata(alias: model.name, role: model.roleHint, assignedServices: [])
          metadata[model.id] = ModelMetadata(
            alias: current.alias, role: current.role, assignedServices: current.assignedServices,
            isPinned: !current.isPinned)
          manager.updateModelMetadata(metadata)
        } label: {
          Image(systemName: metadata?.isPinned == true ? "pin.fill" : "pin")
        }
        .buttonStyle(AppleIconButtonStyle())
        .help(metadata?.isPinned == true ? "Unpin model" : "Pin model")
        Button("Edit", action: onEdit).buttonStyle(AppleSecondaryButtonStyle())
        Button("Delete", role: .destructive, action: onDelete).buttonStyle(
          AppleDestructiveButtonStyle())
      }
      HStack(spacing: 8) {
        Text("Assign to:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(services.filter { service in compatible(service) }) { service in
          HStack(spacing: 5) {
            Toggle(
              service.definition.name,
              isOn: Binding(
                get: { metadata?.assignedServices.contains(service.id) == true },
                set: { onAssign(service.id, $0) })
            )
            .toggleStyle(.checkbox).font(.caption)
            if metadata?.assignedServices.contains(service.id) == true {
              Button {
                settingsService = service.id
              } label: {
                Image(systemName: "slider.horizontal.3")
              }
              .buttonStyle(AppleIconButtonStyle()).help("Configure this model assignment")
            }
          }
        }
      }
    }
    .appCard(padding: 14)
    .sheet(item: $settingsService) { serviceID in
      ModelAssignmentSettingsSheet(serviceID: serviceID, role: nil, manager: manager)
    }
  }

  private var detail: String {
    [
      model.runtime.title,
      model.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
      model.roleHint.rawValue, model.supportsVision ? "Vision" : nil,
    ].compactMap { $0 }.joined(separator: " · ")
  }

  private func compatible(_ service: ServiceSnapshot) -> Bool {
    model.runtime == .llamaCpp
  }

}

struct ModelAssignmentSettingsSheet: View {
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

struct AddModelSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var manager: ServiceManager
  @ObservedObject var recommendations: RecommendationStore
  @State private var query = ""
  @State private var selected: ModelRecommendation?
  @ObservedObject var downloads: ModelDownloadCoordinator

  init(
    manager: ServiceManager, recommendations: RecommendationStore,
    downloads: ModelDownloadCoordinator
  ) {
    self.manager = manager
    self.recommendations = recommendations
    self.downloads = downloads
  }

  private var results: [ModelRecommendation] {
    recommendations.recommendations.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
    }.prefix(30).map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      PageHeader(
        eyebrow: "Library", title: "Add model",
        subtitle: "Choose a compatible catalog model to download.", symbol: "arrow.down.circle")
      HStack {
        TextField("Search catalog", text: $query).textFieldStyle(.plain).appInputSurface()
        Button {
          Task { await recommendations.refresh() }
        } label: {
          Label("Refresh catalog", systemImage: "arrow.clockwise")
        }.buttonStyle(AppleSecondaryButtonStyle())
      }
      if results.isEmpty {
        FriendlyEmptyState(
          symbol: "magnifyingglass", title: "No catalog results",
          message: "Refresh recommendations or try another search.")
      } else {
        List(results) { model in
          Button {
            selected = model
          } label: {
            HStack {
              VStack(alignment: .leading) {
                Text(model.name).font(.headline)
                Text("\(model.runtime) · \(model.sizeText) · \(model.role.rawValue)").font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              CompatibilityBadge(compatibility: model.compatibility)
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
      HStack {
        Spacer()
        Button("Close") { dismiss() }.buttonStyle(AppleSecondaryButtonStyle())
      }
    }
    .padding(24).frame(width: 700, height: 560)
    .task { if recommendations.recommendations.isEmpty { await recommendations.refresh() } }
  }
}

struct EditModelSheet: View {
  @Environment(\.dismiss) private var dismiss
  let model: DiscoveredModel
  @ObservedObject var manager: ServiceManager
  @State private var alias: String
  @State private var role: RecommendationRole

  init(model: DiscoveredModel, manager: ServiceManager) {
    self.model = model
    self.manager = manager
    let metadata = manager.modelMetadata[model.id]
    _alias = State(initialValue: metadata?.alias ?? model.name)
    _role = State(initialValue: metadata?.role ?? model.roleHint)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      PageHeader(eyebrow: "Model", title: "Edit model", subtitle: model.name, symbol: "pencil")
      TextField("Display name", text: $alias).textFieldStyle(.plain).appInputSurface()
      ThemedMenuPicker(
        choices: RecommendationRole.allCases.map { ($0.rawValue, $0) }, selection: $role)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(AppleSecondaryButtonStyle())
        Button("Save") { save() }.buttonStyle(ApplePrimaryButtonStyle())
      }
    }.padding(24).frame(width: 440)
  }

  private func save() {
    var metadata = manager.modelMetadata
    metadata[model.id] = ModelMetadata(
      alias: alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.name : alias,
      role: role, assignedServices: metadata[model.id]?.assignedServices ?? [],
      isPinned: metadata[model.id]?.isPinned ?? false)
    manager.updateModelMetadata(metadata)
    dismiss()
  }
}

extension ModelRuntime {
  var title: String { "llama.cpp" }
  static var allCases: [ModelRuntime] { [.llamaCpp] }
}
