import Foundation

enum ChatMessageRole: String, Codable, CaseIterable, Sendable {
  case system, user, assistant
}

struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let role: ChatMessageRole
  var content: String
  let createdAt: Date

  init(
    id: UUID = UUID(), role: ChatMessageRole, content: String, createdAt: Date = Date()
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.createdAt = createdAt
  }
}

struct ChatConversation: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var title: String
  var messages: [ChatMessage]
  var serviceID: ServiceID
  var modelName: String
  let createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(), title: String = "New conversation", messages: [ChatMessage] = [],
    serviceID: ServiceID = .llamaChat, modelName: String = "", createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.messages = messages
    self.serviceID = serviceID
    self.modelName = modelName
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

struct ChatServiceOption: Equatable, Identifiable, Sendable {
  let serviceID: ServiceID
  let name: String
  let modelName: String
  let endpoint: URL?
  let state: ServiceState
  let securitySummary: String

  var id: ServiceID { serviceID }
  var isAvailable: Bool { endpoint != nil && state == .running }
}

struct ChatRequest: Equatable, Sendable {
  let model: String
  let messages: [ChatMessage]
  let generation: GenerationProfile
}

struct ChatUsage: Equatable, Sendable {
  let promptTokens: Int?
  let completionTokens: Int?
  let totalTokens: Int?
}

struct ChatUsageMetrics: Equatable, Sendable {
  let timeToFirstToken: TimeInterval?
  let tokensPerSecond: Double?
  let usage: ChatUsage?
}

enum ChatStreamEvent: Equatable, Sendable {
  case text(String)
  case completed(ChatUsage?)
}

enum ChatTransportError: LocalizedError, Equatable {
  case invalidEndpoint
  case requestFailed(Int)
  case serverMessage(String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "The selected service endpoint is invalid."
    case .requestFailed(let status): "The model service returned HTTP \(status)."
    case .serverMessage(let message): message
    case .invalidResponse: "The model service returned an unreadable response."
    }
  }
}

protocol ChatTransporting: Sendable {
  func stream(
    request: ChatRequest, endpoint: URL
  ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

protocol ChatConversationStoring: Sendable {
  func load() async -> [ChatConversation]
  func save(_ conversations: [ChatConversation]) async throws
}

enum ChatPersistenceError: LocalizedError, Equatable {
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .encodingFailed: "Mochi could not save the Studio conversations."
    }
  }
}

protocol ChatServiceHealthChecking: Sendable {
  func check(endpoint: URL) async -> Bool
}

