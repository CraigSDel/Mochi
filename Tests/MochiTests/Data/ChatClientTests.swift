import XCTest

@testable import Mochi

final class ChatClientTests: XCTestCase {
  func test_stream_decodesTextAndUsage() async throws {
    let streaming = StubChatStreaming(
      statusCode: 200,
      lines: [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}",
        "event: ping",
        "data: {malformed}",
        "data: {\"choices\":[{\"delta\":{}}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":1,\"total_tokens\":4}}",
        "data: [DONE]"
      ])
    let client = OpenAICompatibleClient(streaming: streaming)
    let events = try await collectChatEvents(
      client.stream(request: makeRequest(), endpoint: XCTUnwrapURL("http://localhost/v1")))

    XCTAssertEqual(events, [
      .text("Hi"),
      .completed(.init(promptTokens: 3, completionTokens: 1, totalTokens: 4))
    ])
    XCTAssertEqual(streaming.request?.url?.path, "/v1/chat/completions")
    XCTAssertEqual(streaming.request?.httpMethod, "POST")
    XCTAssertEqual(streaming.request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    let body = try XCTUnwrap(streaming.request?.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["model"] as? String, "local")
    XCTAssertEqual(json["stream"] as? Bool, true)
  }

  func test_stream_surfacesServerMessage() async {
    let streaming = StubChatStreaming(
      statusCode: 500, lines: ["{\"error\":{\"message\":\"model unavailable\"}}"])
    let client = OpenAICompatibleClient(streaming: streaming)

    do {
      _ = try await collectChatEvents(
        client.stream(request: makeRequest(), endpoint: XCTUnwrapURL("http://localhost/v1")))
      XCTFail("Expected server error")
    } catch {
      XCTAssertEqual(error as? ChatTransportError, .serverMessage("model unavailable"))
    }
  }

  func test_stream_surfacesHTTPStatusWhenServerHasNoMessage() async {
    let streaming = StubChatStreaming(statusCode: 429, lines: ["not json"])
    let client = OpenAICompatibleClient(streaming: streaming)

    do {
      _ = try await collectChatEvents(
        client.stream(request: makeRequest(), endpoint: XCTUnwrapURL("http://localhost/v1")))
      XCTFail("Expected server error")
    } catch {
      XCTAssertEqual(error as? ChatTransportError, .requestFailed(429))
    }
  }

  func test_stream_cancellation_finishesWithoutError() async throws {
    let streaming = StubChatStreaming(
      statusCode: 200, lines: ["data: {\"choices\":[]}"], holdOpen: true)
    let client = OpenAICompatibleClient(streaming: streaming)
    let request = makeRequest()
    let endpoint = XCTUnwrapURL("http://localhost/v1")
    let task = Task {
      try await collectChatEvents(
        client.stream(request: request, endpoint: endpoint))
    }
    try await Task.sleep(for: .milliseconds(5))
    task.cancel()
    _ = try? await task.value
    XCTAssertTrue(streaming.wasCancelled)
  }

  func test_transportError_interpolatesHTTPStatus() {
    XCTAssertEqual(
      ChatTransportError.requestFailed(503).errorDescription,
      "The model service returned HTTP 503.")
  }

  func test_generationUseCase_emitsMetricsAndPreservesUsage() async throws {
    let transport = StubChatTransport(events: [
      .text("Hi"), .completed(.init(promptTokens: 2, completionTokens: 3, totalTokens: 5))
    ])
    let clock = SequenceClock(values: [
      Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 101),
      Date(timeIntervalSince1970: 102)
    ])
    let useCase = ChatGenerationUseCase(transport: transport, now: { clock.next() })

    let events = try await collectGenerationEvents(
      useCase.generate(request: makeRequest(), endpoint: XCTUnwrapURL("http://localhost/v1")))

    XCTAssertEqual(events.first, .text("Hi"))
    let metrics = try XCTUnwrap(events.compactMap { event -> ChatUsageMetrics? in
      if case .metrics(let value) = event { return value }
      return nil
    }.last)
    XCTAssertEqual(metrics.timeToFirstToken, 1)
    XCTAssertEqual(metrics.tokensPerSecond, 3)
    XCTAssertEqual(metrics.usage?.totalTokens, 5)
  }

  func test_healthChecker_requestsModelsEndpoint_andAcceptsSuccess() async {
    let fetcher = StubFetcher()
    fetcher.stub(pathSuffix: "/v1/models", statusCode: 200)
    let checker = OpenAICompatibleHealthChecker(fetcher: fetcher)

    let result = await checker.check(endpoint: XCTUnwrapURL("http://127.0.0.1:11437/v1"))

    XCTAssertTrue(result)
    XCTAssertEqual(fetcher.requestCount(matching: "/v1/models"), 1)
  }

  func test_healthChecker_returnsFalseForUnavailableService() async {
    let fetcher = StubFetcher()
    fetcher.stub(pathSuffix: "/v1/models", statusCode: 503)
    let checker = OpenAICompatibleHealthChecker(fetcher: fetcher)

    let result = await checker.check(endpoint: XCTUnwrapURL("http://127.0.0.1:11437/v1"))

    XCTAssertFalse(result)
  }

  private func XCTUnwrapURL(_ value: String) -> URL {
    URL(string: value)!
  }

  private func makeRequest() -> ChatRequest {
    .init(model: "local", messages: [], generation: .balanced)
  }

}

private func collectChatEvents(
  _ stream: AsyncThrowingStream<ChatStreamEvent, Error>
) async throws -> [ChatStreamEvent] {
  var result: [ChatStreamEvent] = []
  for try await event in stream { result.append(event) }
  return result
}

private func collectGenerationEvents(
  _ stream: AsyncThrowingStream<StudioGenerationEvent, Error>
) async throws -> [StudioGenerationEvent] {
  var result: [StudioGenerationEvent] = []
  for try await event in stream { result.append(event) }
  return result
}

private final class StubChatTransport: ChatTransporting, @unchecked Sendable {
  let events: [ChatStreamEvent]

  init(events: [ChatStreamEvent]) { self.events = events }

  func stream(
    request: ChatRequest, endpoint: URL
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish()
    }
  }
}

private final class SequenceClock: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Date]

  init(values: [Date]) { self.values = values }

  func next() -> Date { lock.withLock { values.removeFirst() } }
}

private final class StubChatStreaming: ChatStreaming, @unchecked Sendable {
  let statusCode: Int
  let responseLines: [String]
  let holdOpen: Bool
  private(set) var request: URLRequest?
  private(set) var wasCancelled = false

  init(statusCode: Int, lines: [String], holdOpen: Bool = false) {
    self.statusCode = statusCode
    responseLines = lines
    self.holdOpen = holdOpen
  }

  func stream(for request: URLRequest) async throws -> ChatHTTPStream {
    self.request = request
    return ChatHTTPStream(statusCode: statusCode, lines: AsyncThrowingStream { continuation in
      let task = Task {
        for line in responseLines {
          try? await Task.sleep(for: .milliseconds(1))
          guard !Task.isCancelled else { return }
          continuation.yield(line)
        }
        if holdOpen {
          while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        } else {
          continuation.finish()
        }
      }
      continuation.onTermination = { [weak self] _ in
        self?.wasCancelled = true
        task.cancel()
      }
    })
  }
}
