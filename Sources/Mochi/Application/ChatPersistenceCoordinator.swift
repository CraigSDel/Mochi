import Foundation

actor ChatPersistenceCoordinator: ChatConversationStoring {
  private let store: any ChatConversationStoring
  private var pending: ([ChatConversation], Int)?
  private var nextRevision = 0
  private var isSaving = false

  init(store: any ChatConversationStoring) { self.store = store }

  func load() async -> [ChatConversation] { await store.load() }

  func save(_ conversations: [ChatConversation]) async throws {
    nextRevision += 1
    pending = (conversations, nextRevision)
    guard !isSaving else { return }
    isSaving = true
    var lastError: Error?
    while let work = pending {
      pending = nil
      do {
        try await store.save(work.0)
      } catch {
        lastError = error
      }
    }
    isSaving = false
    if let lastError { throw lastError }
  }
}
