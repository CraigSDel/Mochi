import AppKit
import SwiftUI

struct ServiceConfigurationEditor: View {
  let serviceID: ServiceID
  @ObservedObject var manager: ServiceManager
  @ObservedObject var recommendations: RecommendationStore
  let openModels: () -> Void
  @State private var advanced = false
  @AppStorage private var includeCatalog: Bool
  init(
    serviceID: ServiceID, manager: ServiceManager, recommendations: RecommendationStore,
    openModels: @escaping () -> Void
  ) {
    self.serviceID = serviceID
    self.manager = manager
    self.recommendations = recommendations
    self.openModels = openModels
    _includeCatalog = AppStorage(wrappedValue: true, ModelCatalogPreferences.key(for: serviceID))
  }
  private var configuration: ServiceLaunchConfiguration { manager.configuration(for: serviceID) }
  private var locked: Bool { manager.isConfigurationLocked(serviceID) }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeading(
          "Connection", subtitle: "Choose where this service listens and how models are resolved.",
          symbol: "network")
        HStack(alignment: .top, spacing: 12) {
          ConfigurationField("Port") {
            TextField("Port", value: commonBinding(\.port), format: .number)
              .textFieldStyle(.plain)
              .appInputSurface()
          }
          .frame(maxWidth: 150)
          ConfigurationField("Network") {
            ThemedMenuPicker(
              choices: BindMode.allCases.map { ($0.title, $0) },
              selection: commonBinding(\.bindMode)
            )
          }
          ConfigurationField("Model downloads") {
            ThemedMenuPicker(
              choices: DownloadPolicy.allCases.map { ($0.title, $0) },
              selection: commonBinding(\.downloadPolicy)
            )
          }
        }
      }
      .disabled(locked)
      .appCard()

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          SectionHeading(
            "Model", subtitle: "Choose a cached or recommended Hugging Face GGUF.",
            symbol: "shippingbox")
          Spacer()
          CatalogVisibilityPicker(includeCatalog: $includeCatalog)
          Button {
            Task { await manager.refreshModelInventory() }
          } label: {
            Label("Rescan", systemImage: "arrow.clockwise")
          }
          .buttonStyle(AppleSecondaryButtonStyle()).help("Rescan downloaded models")
        }
        llamaFields
      }
      .disabled(locked)
      .appCard()

      PerformanceTuningEditor(serviceID: serviceID, manager: manager)

      VStack(alignment: .leading, spacing: 12) {
        DisclosureGroup("Advanced", isExpanded: $advanced) {
          llamaAdvanced
        }
        .font(.headline)
        .disabled(locked)
        let issues = manager.validationIssues(for: serviceID)
        ForEach(issues) { issue in
          Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.red)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        HStack {
          if locked {
            Label("Stop the service to edit its configuration.", systemImage: "lock.fill")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Reset to Defaults") { manager.resetConfiguration(serviceID) }
            .buttonStyle(AppleSecondaryButtonStyle())
            .disabled(locked || configuration == .defaultValue(for: serviceID))
        }
      }
      .appCard()
    }
  }

  private var llamaFields: some View {
    VStack(alignment: .leading, spacing: 8) {
      DownloadableModelSelector(
        title: "Model", options: llamaOptions, selection: llamaSelection,
        recommendations: recommendations.recommendations, manager: manager,
        onSelect: { option in
          guard let repository = option.repository, let filename = option.filename else { return }
          var copy = configuration
          copy.llama?.repository = repository
          copy.llama?.filename = filename
          copy.llama?.alias = option.name
          manager.updateConfiguration(copy, for: serviceID)
        }, onManageDownloads: openModels)
    }
  }
  private var llamaAdvanced: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Custom model").font(.subheadline.weight(.semibold))
      VStack(alignment: .leading, spacing: 8) {
        TextField("Hugging Face repository", text: llamaBinding(\.repository))
        TextField("GGUF filename", text: llamaBinding(\.filename))
        TextField("Model alias", text: llamaBinding(\.alias))
      }
    }.padding(.top, 8)
  }
  private var modelRole: RecommendationRole {
    switch serviceID {
    case .autocomplete: .coding
    case .embeddings: .embedding
    case .llamaChat: .chat
    }
  }
  private var llamaOptions: [ModelOption] {
    ModelOptionBuilder.options(
      runtime: .llamaCpp, role: modelRole, installed: manager.installedModels,
      recommendations: recommendations.recommendations, currentLlama: configuration.llama,
      includeCatalog: includeCatalog)
  }
  private var llamaSelection: String {
    guard let llama = configuration.llama else { return "" }
    let key = "\(llama.repository)|\(llama.filename)"
    return llamaOptions.first { ModelOptionBuilder.selectionKey($0) == key }?.id ?? ""
  }
  private func commonBinding<Value>(_ keyPath: WritableKeyPath<ServiceLaunchConfiguration, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { configuration[keyPath: keyPath] },
      set: { value in
        var copy = configuration
        copy[keyPath: keyPath] = value
        manager.updateConfiguration(copy, for: serviceID)
      })
  }
  private func llamaBinding<Value>(_ keyPath: WritableKeyPath<LlamaLaunchConfiguration, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { configuration.llama![keyPath: keyPath] },
      set: { value in
        var copy = configuration
        copy.llama![keyPath: keyPath] = value
        manager.updateConfiguration(copy, for: serviceID)
      })
  }
}
