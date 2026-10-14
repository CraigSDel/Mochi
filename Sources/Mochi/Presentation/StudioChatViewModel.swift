import Combine
import Foundation

@MainActor
final class StudioChatViewModel: ObservableObject {
  @Published private(set) var conversations: [ChatConversation] = []
  @Published private(set) var selectedConversationID: UUID?
  @Published private(set) var isSending = false
  @Published private(set) var isCheckingHealth = false
  @Published private(set) var readiness: StudioReadiness = .checking
  @Published private(set) var usageMetrics: ChatUsageMetrics?
  @Published private(set) var persistenceError: String?
  @Published var draft = ""
  @Published var errorMessage: String?

  let generator: any ChatGenerating
  let conversationStore: any ChatConversationStoring
  let healthChecker: any ChatServiceHealthChecking
  private var sendTask: Task<Void, Never>?
  private var persistenceTask: Task<Void, Never>?
  private var healthCheckID = UUID()
  private var healthyEndpoint: URL?
  private let now: @Sendable () -> Date

  init(
    generator: any ChatGenerating,
    conversationStore: any ChatConversationStoring,
    healthChecker: any ChatServiceHealthChecking,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.generator = generator
    self.conversationStore = conversationStore
    self.healthChecker = healthChecker
    self.now = now
  }

  var isHealthy: Bool { readiness == .ready }

  var selectedConversation: ChatConversation? {
    conversations.first { $0.id == selectedConversationID }
  }

  func load() async {
    conversations = await conversationStore.load()
    selectedConversationID = conversations.first?.id
  }

  func newConversation(service: ChatServiceOption) {
    let conversation = ChatConversation(serviceID: service.serviceID, modelName: service.modelName)
    conversations.insert(conversation, at: 0)
    selectedConversationID = conversation.id
    draft = ""
    persist()
  }

  func select(_ conversation: ChatConversation) {
    cancelGeneration()
    selectedConversationID = conversation.id
    errorMessage = nil
  }

  func switchService(_ service: ChatServiceOption, for conversation: ChatConversation) {
    guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
    cancelGeneration()
    conversations[index].serviceID = service.serviceID
    conversations[index].modelName = service.modelName
    selectedConversationID = conversation.id
    persist()
  }

  func remove(_ conversation: ChatConversation) {
    conversations.removeAll { $0.id == conversation.id }
    selectedConversationID = conversations.first?.id
    persist()
  }

  func checkHealth(service: ChatServiceOption) async {
    guard let endpoint = service.endpoint else {
      healthCheckID = UUID()
      isCheckingHealth = false
      healthyEndpoint = nil
      readiness = .unavailable
      return
    }
    guard service.state == .running else {
      healthCheckID = UUID()
      isCheckingHealth = false
      healthyEndpoint = nil
      readiness = .stopped
      return
    }
    isCheckingHealth = true
    readiness = .checking
    healthyEndpoint = nil
    let checkID = UUID()
    healthCheckID = checkID
    let healthy = await healthChecker.check(endpoint: endpoint)
    guard checkID == healthCheckID else { return }
    readiness = healthy ? .ready : .unhealthy
    healthyEndpoint = healthy ? endpoint : nil
    isCheckingHealth = false
  }

  func send(service: ChatServiceOption, generation: GenerationProfile) {
    guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let endpoint = service.endpoint, service.state == .running, readiness == .ready,
      healthyEndpoint == endpoint
    else { return }
    if selectedConversation == nil { newConversation(service: service) }
    guard let conversationID = selectedConversationID,
      let index = conversations.firstIndex(where: { $0.id == conversationID })
    else { return }
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    draft = ""
    conversations[index].serviceID = service.serviceID
    conversations[index].modelName = service.modelName
    conversations[index].messages.append(.init(role: .user, content: prompt))
    conversations[index].title = conversations[index].messages.count == 1
      ? String(prompt.prefix(42)) : conversations[index].title
    conversations[index].messages.append(.init(role: .assistant, content: ""))
    conversations[index].updatedAt = now()
    persist()
    isSending = true
    errorMessage = nil
    usageMetrics = nil
    let requestMessages = Array(conversations[index].messages.dropLast())
    let request = ChatRequest(
      model: service.modelName, messages: requestMessages, generation: generation)
    sendTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await event in generator.generate(request: request, endpoint: endpoint) {
          guard !Task.isCancelled else { return }
          switch event {
          case .text(let text):
            if let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[index].messages.lastIndex(where: {
                $0.role == .assistant
              })
            {
              conversations[index].messages[messageIndex].content += text
              conversations[index].updatedAt = now()
              objectWillChange.send()
            }
          case .metrics(let metrics): usageMetrics = metrics
          }
        }
        persist()
      } catch is CancellationError {
      } catch {
        errorMessage = error.localizedDescription
        removeEmptyAssistantMessage(conversationID: conversationID)
      }
      isSending = false
    }
  }

  func cancelSending() {
    cancelGeneration()
  }

  private func cancelGeneration() {
    sendTask?.cancel()
    sendTask = nil
    isSending = false
    persist()
  }

  func regenerate(service: ChatServiceOption, generation: GenerationProfile) {
    guard let conversationID = selectedConversationID,
      let index = conversations.firstIndex(where: { $0.id == conversationID }),
      let assistant = conversations[index].messages.last,
      assistant.role == .assistant,
      let user = conversations[index].messages.dropLast().last,
      user.role == .user
    else { return }
    cancelGeneration()
    conversations[index].messages.removeLast(2)
    draft = user.content
    send(service: service, generation: generation)
  }

  private func removeEmptyAssistantMessage(conversationID: UUID) {
    guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
    conversations[index].messages.removeAll { $0.role == .assistant && $0.content.isEmpty }
    persist()
  }

  private func persist() {
    let snapshot = conversations
    let previous = persistenceTask
    persistenceTask = Task { [weak self, conversationStore] in
      await previous?.value
      do {
        try await conversationStore.save(snapshot)
      } catch {
        self?.persistenceError = error.localizedDescription
      }
    }
  }
}
