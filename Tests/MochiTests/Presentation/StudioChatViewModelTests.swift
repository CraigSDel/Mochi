import XCTest

@testable import Mochi

@MainActor
final class StudioChatViewModelTests: XCTestCase {
  func test_send_appendsResponseAndPersistsConversation() async throws {
    let store = TestConversationStore()
    let model = makeViewModel(store: store, generator: TestChatGenerator(events: [.text("Hello")]))
    let service = availableService()
    model.newConversation(service: service)
    model.draft = "Hi"
    await model.checkHealth(service: service)
    model.send(service: service, generation: .balanced)
    await eventually { !model.isSending }

    XCTAssertEqual(model.selectedConversation?.messages.map(\.content), ["Hi", "Hello"])
    XCTAssertEqual(store.saved.last?.first?.messages.count, 2)
  }

  func test_stopGeneration_keepsPartialResponseAndPersists() async throws {
    let store = TestConversationStore()
    let generator = TestChatGenerator(events: [.text("Partial")], holdOpen: true)
    let model = makeViewModel(store: store, generator: generator)
    let service = availableService()
    model.newConversation(service: service)
    model.draft = "Continue"
    await model.checkHealth(service: service)
    model.send(service: service, generation: .balanced)
    await eventually { model.selectedConversation?.messages.last?.content == "Partial" }
    model.cancelSending()
    await eventually { store.saved.last?.first?.messages.last?.content == "Partial" }

    XCTAssertFalse(model.isSending)
    XCTAssertEqual(model.selectedConversation?.messages.last?.content, "Partial")
    XCTAssertEqual(store.saved.last?.first?.messages.last?.content, "Partial")
  }

  func test_regenerate_replacesLastTurn() async throws {
    let first = ChatConversation(
      title: "Hi", messages: [
        .init(role: .user, content: "Hi"), .init(role: .assistant, content: "Old")
      ], serviceID: .llamaChat, modelName: "local")
    let store = TestConversationStore(initial: [first])
    let model = makeViewModel(store: store, generator: TestChatGenerator(events: [.text("New")]))
    await model.load()
    await model.checkHealth(service: availableService())
    model.regenerate(service: availableService(), generation: .balanced)
    await eventually { !model.isSending }

    XCTAssertEqual(model.selectedConversation?.messages.map(\.content), ["Hi", "New"])
  }

  func test_send_doesNothingForMissingOrUnhealthyService() async {
    let model = makeViewModel(
      store: TestConversationStore(), generator: TestChatGenerator(events: [.text("bad")]))
    model.draft = "Hi"
    model.send(service: .init(
      serviceID: .llamaChat, name: "Chat", modelName: "local", endpoint: nil,
      state: .stopped, securitySummary: "unavailable"), generation: .balanced)

    XCTAssertTrue(model.conversations.isEmpty)
    XCTAssertFalse(model.isSending)
  }

  func test_unhealthyServiceBlocksSendAndPublishesReadiness() async {
    let model = StudioChatViewModel(
      generator: TestChatGenerator(events: [.text("bad")]),
      conversationStore: TestConversationStore(),
      healthChecker: TestHealthChecker(result: false))
    let service = availableService()
    await model.checkHealth(service: service)
    model.draft = "Hi"
    model.send(service: service, generation: .balanced)

    XCTAssertEqual(model.readiness, .unhealthy)
    XCTAssertTrue(model.conversations.isEmpty)
  }

  func test_missingEndpointPublishesUnavailableReadiness() async {
    let model = makeViewModel(
      store: TestConversationStore(), generator: TestChatGenerator(events: []))
    let service = ChatServiceOption(
      serviceID: .llamaChat, name: "Chat", modelName: "local", endpoint: nil,
      state: .stopped, securitySummary: "unavailable")

    await model.checkHealth(service: service)

    XCTAssertEqual(model.readiness, .unavailable)
  }

  func test_persistenceFailureIsPublished() async {
    let store = TestConversationStore(shouldFail: true)
    let model = makeViewModel(store: store, generator: TestChatGenerator(events: []))

    model.newConversation(service: availableService())
    await eventually { model.persistenceError != nil }

    XCTAssertEqual(model.persistenceError, "test persistence failure")
  }

  func test_usageMetrics_recordsFirstTokenRateAndCounts() async throws {
    let clock = TestClock(values: [
      Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 101),
      Date(timeIntervalSince1970: 101), Date(timeIntervalSince1970: 102)
    ])
    let generator = TestChatGenerator(events: [
      .text("Hi"), .metrics(.init(
        timeToFirstToken: 1, tokensPerSecond: 4,
        usage: .init(promptTokens: 5, completionTokens: 4, totalTokens: 9)))
    ])
    let model = makeViewModel(
      store: TestConversationStore(), generator: generator, now: { clock.next() })
    let service = availableService()
    model.newConversation(service: service)
    model.draft = "Hi"
    await model.checkHealth(service: service)
    model.send(service: service, generation: .balanced)
    await eventually { !model.isSending }

    XCTAssertEqual(model.usageMetrics?.timeToFirstToken, 1)
    XCTAssertEqual(model.usageMetrics?.tokensPerSecond, 4)
    XCTAssertEqual(model.usageMetrics?.usage?.promptTokens, 5)
  }

  private func makeViewModel(
    store: TestConversationStore,
    generator: TestChatGenerator,
    now: @escaping @Sendable () -> Date = Date.init
  ) -> StudioChatViewModel {
    StudioChatViewModel(
      generator: generator, conversationStore: store,
      healthChecker: TestHealthChecker(result: true), now: now)
  }

  private func availableService() -> ChatServiceOption {
    .init(
      serviceID: .llamaChat, name: "Chat", modelName: "local",
      endpoint: URL(string: "http://localhost/v1"), state: .running,
      securitySummary: "local")
  }

  private func eventually(
    timeout: TimeInterval = 1, condition: @escaping @MainActor () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }
}

private final class TestChatGenerator: ChatGenerating, @unchecked Sendable {
  let events: [StudioGenerationEvent]
  let holdOpen: Bool

  init(events: [StudioGenerationEvent], holdOpen: Bool = false) {
    self.events = events
    self.holdOpen = holdOpen
  }

  func generate(
    request: ChatRequest, endpoint: URL
  ) -> AsyncThrowingStream<StudioGenerationEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        for event in events { continuation.yield(event) }
        if !holdOpen { continuation.finish() }
        else {
          while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

private final class TestConversationStore: ChatConversationStoring, @unchecked Sendable {
  private(set) var saved: [[ChatConversation]] = []
  var initial: [ChatConversation]
  let shouldFail: Bool

  init(initial: [ChatConversation] = [], shouldFail: Bool = false) {
    self.initial = initial
    self.shouldFail = shouldFail
  }
  func load() async -> [ChatConversation] { initial }
  func save(_ conversations: [ChatConversation]) async throws {
    if shouldFail { throw TestPersistenceError.failure }
    saved.append(conversations)
  }
}

private enum TestPersistenceError: LocalizedError {
  case failure
  var errorDescription: String? { "test persistence failure" }
}

private struct TestHealthChecker: ChatServiceHealthChecking {
  let result: Bool
  func check(endpoint: URL) async -> Bool { result }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Date]

  init(values: [Date]) { self.values = values }
  func next() -> Date {
    lock.withLock {
      if values.count > 1 { return values.removeFirst() }
      return values.first ?? Date(timeIntervalSince1970: 0)
    }
  }
}
