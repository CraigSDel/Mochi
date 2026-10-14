import XCTest

@testable import Mochi

final class ChatPersistenceTests: XCTestCase {
  func test_store_roundTripsConversationsAndOrdersNewestFirst() async throws {
    let suite = "Mochi.ChatPersistenceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsChatConversationStore(defaults: defaults)
    let older = ChatConversation(updatedAt: Date(timeIntervalSince1970: 1))
    let newer = ChatConversation(updatedAt: Date(timeIntervalSince1970: 2))

    try await store.save([older, newer])
    let result = await store.load()

    XCTAssertEqual(result.map(\.id), [newer.id, older.id])
  }
}
