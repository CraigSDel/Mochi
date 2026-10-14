import XCTest

@testable import Mochi

final class ChatPersistenceCoordinatorTests: XCTestCase {
  func test_saveSerializesRapidSnapshotsAndKeepsNewestState() async throws {
    let store = DelayedConversationStore()
    let coordinator = ChatPersistenceCoordinator(store: store)
    let first = ChatConversation(title: "first")
    let second = ChatConversation(title: "second")

    async let firstSave: Void = coordinator.save([first])
    try? await Task.sleep(for: .milliseconds(2))
    async let secondSave: Void = coordinator.save([second])
    _ = try await (firstSave, secondSave)

    let saved = await store.saved
    XCTAssertEqual(saved.map { $0.first?.title }, ["first", "second"])
  }

  func test_loadDelegatesWithoutChangingPersistedShape() async {
    let conversation = ChatConversation(title: "saved")
    let store = DelayedConversationStore(initial: [conversation])
    let coordinator = ChatPersistenceCoordinator(store: store)

    let loaded = await coordinator.load()

    XCTAssertEqual(loaded, [conversation])
  }
}

private actor DelayedConversationStore: ChatConversationStoring {
  private(set) var saved: [[ChatConversation]] = []
  private let initial: [ChatConversation]

  init(initial: [ChatConversation] = []) { self.initial = initial }

  func load() async -> [ChatConversation] { initial }

  func save(_ conversations: [ChatConversation]) async throws {
    if saved.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    saved.append(conversations)
  }
}
