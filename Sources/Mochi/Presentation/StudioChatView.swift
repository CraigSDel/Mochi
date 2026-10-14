import SwiftUI

struct StudioChatView: View {
  @ObservedObject var manager: ServiceManager
  @ObservedObject var viewModel: StudioChatViewModel
  @ObservedObject var memoryMonitor: MemoryMonitor
  @State private var showingExport = false
  @State private var didLoad = false

  private var services: [ChatServiceOption] { manager.chatServiceOptions() }
  private var selectedService: ChatServiceOption? {
    let id = viewModel.selectedConversation?.serviceID
    return services.first { $0.serviceID == id } ?? services.first
  }
  private var generation: GenerationProfile {
    manager.configuration(for: .llamaChat).llama?.generation ?? .balanced
  }

  var body: some View {
    HStack(spacing: 0) {
      conversationSidebar
      Divider().overlay(AppTheme.separator)
      chatContent
    }
    .background(AppTheme.pageBackground)
    .task {
      guard !didLoad else { return }
      didLoad = true
      await viewModel.load()
      if let service = selectedService { await viewModel.checkHealth(service: service) }
    }
    .onChange(of: selectedService) { _, service in
      guard let service else { return }
      Task { await viewModel.checkHealth(service: service) }
    }
    .sheet(isPresented: $showingExport) {
      if let service = selectedService,
        let export = ClientConfigurationExportBuilder.make(service: service)
      { ClientExportSheet(service: service, export: export) }
    }
  }

  private var conversationSidebar: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Conversations").font(.headline)
        Spacer()
        Button {
          if let service = selectedService ?? services.first { viewModel.newConversation(service: service) }
        } label: { Image(systemName: "square.and.pencil") }
        .buttonStyle(AppleIconButtonStyle()).help("New conversation")
      }
      if viewModel.conversations.isEmpty {
        FriendlyEmptyState(
          symbol: "bubble.left", title: "No conversations",
          message: "Start a local chat when the Chat service is running.")
      } else {
        ScrollView {
          LazyVStack(spacing: 7) {
            ForEach(viewModel.conversations) { conversation in
              ConversationRow(
                conversation: conversation,
                isSelected: conversation.id == viewModel.selectedConversationID,
                onSelect: { viewModel.select(conversation) },
                onDelete: { viewModel.remove(conversation) })
            }
          }
        }
      }
      Spacer()
    }
    .padding(18).frame(width: 230).background(AppTheme.surface.opacity(0.62))
  }

  private var chatContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        PageHeader(
          eyebrow: "Local workspace", title: "Studio",
          subtitle: "Chat privately with a model running on this Mac.", symbol: "sparkles")
        Spacer()
        if let service = selectedService {
          VStack(alignment: .trailing, spacing: 8) {
            Label(
              readinessTitle,
              systemImage: readinessSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.color(for: viewModel.isHealthy ? .success : .warning))
            if viewModel.readiness != .ready {
              Button("Retry") { Task { await viewModel.checkHealth(service: service) } }
                .buttonStyle(AppleSecondaryButtonStyle())
                .disabled(viewModel.isCheckingHealth)
            }
            ThemedMenuPicker(
              choices: services.map { ($0.name, $0.serviceID) },
              selection: Binding(
                get: { service.serviceID },
                set: { id in
                  if let conversation = viewModel.selectedConversation,
                    let option = services.first(where: { $0.serviceID == id })
                  { viewModel.switchService(option, for: conversation) }
                }))
              .frame(width: 190)
          }
        }
      }
      .padding(.horizontal, 34).padding(.top, 28).padding(.bottom, 18)
      if let service = selectedService, service.isAvailable {
        messageArea(service: service)
      } else { unavailableState }
    }
  }

  private func messageArea(service: ChatServiceOption) -> some View {
    VStack(spacing: 14) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array((viewModel.selectedConversation?.messages ?? []).enumerated()), id: \.element.id) {
              index, message in
              ChatMessageBubble(
                message: message,
                onRegenerate: message.role == .assistant
                  && index == (viewModel.selectedConversation?.messages.count ?? 0) - 1
                  ? { viewModel.regenerate(service: service, generation: generation) } : nil)
                .id(message.id)
            }
          }
          .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
          .padding(.horizontal, 34).padding(.vertical, 12)
        }
        .onChange(of: viewModel.selectedConversation?.messages.count) { _, _ in
          if let id = viewModel.selectedConversation?.messages.last?.id {
            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
          }
        }
      }
      composer(service: service).frame(maxWidth: 760).frame(maxWidth: .infinity)
        .padding(.horizontal, 34).padding(.bottom, 24)
    }
  }

  private func composer(service: ChatServiceOption) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(service.modelName).font(.caption).foregroundStyle(.secondary)
        Text("• \(service.securitySummary)").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Client config") { showingExport = true }.buttonStyle(AppleSecondaryButtonStyle())
      }
      contextIndicators
      HStack(alignment: .bottom, spacing: 10) {
        TextField("Message your local model…", text: $viewModel.draft, axis: .vertical)
          .lineLimit(1...6).textFieldStyle(.plain).appInputSurface().onSubmit { send(service) }
        if viewModel.isSending {
          Button("Stop") { viewModel.cancelSending() }.buttonStyle(AppleDestructiveButtonStyle())
        } else {
          Button("Send") { send(service) }.buttonStyle(ApplePrimaryButtonStyle())
            .disabled(
              viewModel.readiness != .ready
                || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      if let error = viewModel.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
      }
    }.appCard(padding: 14)
  }

  private var contextIndicators: some View {
    HStack(spacing: 12) {
      let context = manager.configuration(for: .llamaChat).llama?.contextSize ?? 0
      Label("Context \(ContextSizeOptions.label(for: context))", systemImage: "text.alignleft")
        .accessibilityLabel("Configured context")
      if let sample = memoryMonitor.currentSample {
        Label(
          "AI \(MemoryFormatting.managedUsage(sample))",
          systemImage: "memorychip")
          .accessibilityLabel("Managed AI memory")
        Label(
          "System \(MemoryFormatting.usage(sample.systemUsedBytes, of: sample.systemTotalBytes))",
          systemImage: "desktopcomputer")
          .accessibilityLabel("Total system memory")
        if sample.readingsMayBeIncomplete {
          Image(systemName: "exclamationmark.triangle").accessibilityLabel("Memory reading incomplete")
        }
      } else {
        Label("Memory waiting for sample", systemImage: "memorychip")
      }
      if let metrics = viewModel.usageMetrics {
        if let firstToken = metrics.timeToFirstToken {
          Text("First token \(firstToken, format: .number.precision(.fractionLength(2)))s")
        }
        if let rate = metrics.tokensPerSecond {
          Text("\(rate, format: .number.precision(.fractionLength(1))) tok/s")
        }
        if let usage = metrics.usage {
          if let prompt = usage.promptTokens { Text("Prompt \(prompt) tok") }
          if let completion = usage.completionTokens { Text("Completion \(completion) tok") }
        }
      }
    }
    .font(.caption2)
    .foregroundStyle(AppTheme.secondaryText)
    .lineLimit(1)
  }

  private func send(_ service: ChatServiceOption) {
    if viewModel.selectedConversation == nil { viewModel.newConversation(service: service) }
    viewModel.send(service: service, generation: generation)
  }

  private var unavailableState: some View {
    FriendlyEmptyState(
      symbol: "power", title: "Start the Chat service",
      message: "Studio becomes available when the configured Chat service is running.")
      .padding(34)
  }

  private var readinessTitle: String {
    switch viewModel.readiness {
    case .checking: "Checking service"
    case .ready: "Healthy"
    case .unavailable: "Endpoint unavailable"
    case .stopped: "Service stopped"
    case .unhealthy: "Service unhealthy"
    }
  }

  private var readinessSymbol: String {
    viewModel.readiness == .ready ? "checkmark.circle.fill" : "circle.dotted"
  }
}
