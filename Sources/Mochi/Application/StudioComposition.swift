import Foundation

@MainActor
enum StudioComposition {
  static func viewModel() -> StudioChatViewModel {
    StudioChatViewModel(
      generator: ChatGenerationUseCase(transport: OpenAICompatibleClient(), now: Date.init),
      conversationStore: ChatPersistenceCoordinator(
        store: UserDefaultsChatConversationStore()),
      healthChecker: OpenAICompatibleHealthChecker(fetcher: URLSessionFetching()))
  }
}
