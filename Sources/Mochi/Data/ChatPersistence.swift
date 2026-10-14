import Foundation

final class UserDefaultsChatConversationStore: ChatConversationStoring, @unchecked Sendable {
  private let defaults: UserDefaults
  private let key = "studio.conversations.v1"

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() async -> [ChatConversation] {
    guard let data = defaults.data(forKey: key),
      let conversations = try? JSONDecoder().decode([ChatConversation].self, from: data)
    else { return [] }
    return conversations.sorted { $0.updatedAt > $1.updatedAt }
  }

  func save(_ conversations: [ChatConversation]) async throws {
    guard let data = try? JSONEncoder().encode(conversations) else {
      throw ChatPersistenceError.encodingFailed
    }
    defaults.set(data, forKey: key)
  }
}
