import SwiftUI
import AppKit

struct ServiceDetail: View {
    let service: ServiceSnapshot
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @State private var logsExpanded = false

    private var canStart: Bool {
        service.state.canStart && service.definition.supported && manager.validationIssues(for: service.id).isEmpty
    }
    private var canStop: Bool { service.state.canStop && service.pid != nil }
    private var logPreview: String {
        let lines = service.logText.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(4).joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    PageHeader(
                        eyebrow: service.definition.runtime,
                        title: service.definition.name,
                        subtitle: service.definition.detail,
                        symbol: service.id.symbolName,
                        tone: service.state.tone
                    )
                    Spacer()
                    StatusBadge(state: service.state)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(service.statusText)
                            .font(.headline)
                            .foregroundStyle(service.state == .failed ? Color.red : Color.primary)
                        Text(service.state == .running ? "The service is responding to health checks." : "Configuration remains available while the service is idle.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let endpoint = service.endpoint {
                        HStack(spacing: 8) {
                            MetadataLabel(title: "Endpoint", value: endpoint, symbol: "network")
                            Button {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(endpoint, forType: .string)
                            } label: { Label("Copy endpoint", systemImage: "doc.on.doc") }
                                .labelStyle(.iconOnly).help("Copy endpoint")
                        }
                        .textSelection(.enabled)
                    } else {
                        MetadataLabel(title: "Port", value: "\(manager.configuration(for: service.id).port)", symbol: "number")
                    }
                }
                .appCard()

                ServiceConfigurationEditor(serviceID: service.id, manager: manager, recommendations: recommendations)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Service controls").font(.headline)
                        Text("Changes are validated before the runtime is launched.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop", role: .destructive) { Task { await manager.stop(service.id) } }.disabled(!canStop)
                    Button("Start Service") { attemptStart(service.id, manager: manager) }
                        .buttonStyle(.borderedProminent).disabled(!canStart)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeading("Runtime log", subtitle: "Recent output from this service.", symbol: "terminal")
                        Spacer()
                        Button { logsExpanded.toggle() } label: {
                            Label(logsExpanded ? "Collapse" : "Expand", systemImage: logsExpanded ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.plain)
                    }
                    Text(service.logText.isEmpty ? "No log output yet." : (logsExpanded ? service.logText : logPreview))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(service.logText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: logsExpanded ? 220 : 72, alignment: .topLeading)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                    HStack {
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(service.logText, forType: .string) }
                            .disabled(service.logText.isEmpty)
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([manager.logURL(service.id)]) }
                        Spacer()
                        Button("Clear", role: .destructive) { manager.clearLog(service.id) }.disabled(service.logText.isEmpty)
                    }
                }
                .appCard()
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ServiceConfigurationEditor: View {
    let serviceID: ServiceID
    @ObservedObject var manager: ServiceManager
    @ObservedObject var recommendations: RecommendationStore
    @State private var advanced = false

    private var configuration: ServiceLaunchConfiguration { manager.configuration(for: serviceID) }
    private var locked: Bool { manager.isConfigurationLocked(serviceID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading("Connection", subtitle: "Choose where this service listens and how models are resolved.", symbol: "network")
                HStack {
                    TextField("Port", value: commonBinding(\.port), format: .number).frame(maxWidth: 160)
                    Picker("Network", selection: commonBinding(\.bindMode)) { ForEach(BindMode.allCases) { Text($0.title).tag($0) } }
                    Picker("Models", selection: commonBinding(\.downloadPolicy)) { ForEach(DownloadPolicy.allCases) { Text($0.title).tag($0) } }
                }
            }
            .disabled(locked)
            .appCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading("Model", subtitle: configuration.llama != nil ? "Choose a cached or recommended Hugging Face GGUF." : "Assign installed or catalog Ollama models by role.", symbol: "shippingbox")
                    Spacer()
                    Button { manager.refreshModelInventory() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Rescan downloaded models")
                }
                if configuration.llama != nil { llamaFields } else if configuration.ollama != nil { ollamaFields }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(locked)
            .appCard()

            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    if configuration.llama != nil { llamaAdvanced } else if configuration.ollama != nil { ollamaAdvanced }
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
                    Button("Reset to Defaults") { manager.resetConfiguration(serviceID) }.disabled(locked || configuration == .defaultValue(for: serviceID))
                }
            }
            .appCard()
        }
    }

    private var llamaFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModelSelector(title: "Model", options: llamaOptions, selection: llamaSelection) { option in
                guard let repository = option.repository, let filename = option.filename else { return }
                var copy = configuration
                copy.llama?.repository = repository
                copy.llama?.filename = filename
                copy.llama?.alias = option.name
                manager.updateConfiguration(copy, for: serviceID)
            }
        }
    }
    private var llamaAdvanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Context size", value: llamaBinding(\.contextSize), format: .number)
                TextField("GPU layers", value: llamaBinding(\.gpuLayers), format: .number)
            }
            DisclosureGroup("Custom model") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Hugging Face repository", text: llamaBinding(\.repository))
                    TextField("GGUF filename", text: llamaBinding(\.filename))
                    TextField("Model alias", text: llamaBinding(\.alias))
                }.padding(.top, 8)
            }
        }.padding(.top, 8)
    }
    private var ollamaFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            ollamaSelector("Chat", role: .chat, keyPath: \.chatModel)
            ollamaSelector("Autocomplete", role: .coding, keyPath: \.autocompleteModel)
            ollamaSelector("Embeddings", role: .embedding, keyPath: \.embeddingModel)
        }
    }
    private var ollamaAdvanced: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Flash attention", isOn: ollamaBinding(\.flashAttention))
            TextField("KV cache type", text: ollamaBinding(\.kvCacheType))
            HStack {
                TextField("Context length", value: ollamaBinding(\.contextLength), format: .number)
                TextField("Parallel requests", value: ollamaBinding(\.parallelRequests), format: .number)
                TextField("Max loaded models", value: ollamaBinding(\.maxLoadedModels), format: .number)
            }
            DisclosureGroup("Custom model names") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Chat model", text: ollamaBinding(\.chatModel))
                    TextField("Autocomplete model", text: ollamaBinding(\.autocompleteModel))
                    TextField("Embedding model", text: ollamaBinding(\.embeddingModel))
                }.padding(.top, 8)
            }
        }.padding(.top, 8)
    }
    private var modelRole: RecommendationRole {
        switch serviceID { case .autocomplete: .coding; case .embeddings: .embedding; case .llamaChat, .ollama: .chat }
    }
    private var llamaOptions: [ModelOption] {
        ModelOptionBuilder.options(runtime: .llamaCpp, role: modelRole, installed: manager.installedModels, recommendations: recommendations.recommendations, currentLlama: configuration.llama)
    }
    private var llamaSelection: String {
        guard let llama = configuration.llama else { return "" }
        let key = "\(llama.repository)|\(llama.filename)"
        return llamaOptions.first { ModelOptionBuilder.selectionKey($0) == key }?.id ?? ""
    }
    @ViewBuilder
    private func ollamaSelector(_ title: String, role: RecommendationRole, keyPath: WritableKeyPath<OllamaLaunchConfiguration, String>) -> some View {
        let current = configuration.ollama![keyPath: keyPath]
        let options = ModelOptionBuilder.options(runtime: .ollama, role: role, installed: manager.installedModels, recommendations: recommendations.recommendations, currentOllamaName: current)
        let selection = options.first { ModelOptionBuilder.selectionKey($0) == current }?.id ?? ""
        ModelSelector(title: title, options: options, selection: selection) { option in
            var copy = configuration
            copy.ollama![keyPath: keyPath] = option.name
            manager.updateConfiguration(copy, for: serviceID)
        }
    }
    private func commonBinding<Value>(_ keyPath: WritableKeyPath<ServiceLaunchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in var copy = configuration; copy[keyPath: keyPath] = value; manager.updateConfiguration(copy, for: serviceID) })
    }
    private func llamaBinding<Value>(_ keyPath: WritableKeyPath<LlamaLaunchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration.llama![keyPath: keyPath] }, set: { value in var copy = configuration; copy.llama![keyPath: keyPath] = value; manager.updateConfiguration(copy, for: serviceID) })
    }
    private func ollamaBinding<Value>(_ keyPath: WritableKeyPath<OllamaLaunchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration.ollama![keyPath: keyPath] }, set: { value in var copy = configuration; copy.ollama![keyPath: keyPath] = value; manager.updateConfiguration(copy, for: serviceID) })
    }
}

private struct ModelSelector: View {
    let title: String
    let options: [ModelOption]
    let selection: String
    let onSelect: (ModelOption) -> Void

    var body: some View {
        Picker(title, selection: Binding(get: { selection }, set: { id in
            if let option = options.first(where: { $0.id == id }) { onSelect(option) }
        })) {
            ForEach(options) { option in
                Text("\(option.name) — \(option.detail)").tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}
