import Foundation

enum StudioGenerationEvent: Equatable, Sendable {
  case text(String)
  case metrics(ChatUsageMetrics)
}

protocol ChatGenerating: Sendable {
  func generate(
    request: ChatRequest, endpoint: URL
  ) -> AsyncThrowingStream<StudioGenerationEvent, Error>
}

struct ChatGenerationUseCase: ChatGenerating, Sendable {
  let transport: any ChatTransporting
  let now: @Sendable () -> Date

  func generate(
    request: ChatRequest, endpoint: URL
  ) -> AsyncThrowingStream<StudioGenerationEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let startedAt = now()
          var firstTokenAt: Date?
          var usage: ChatUsage?
          for try await event in transport.stream(request: request, endpoint: endpoint) {
            try Task.checkCancellation()
            switch event {
            case .text(let text):
              if firstTokenAt == nil { firstTokenAt = now() }
              continuation.yield(.text(text))
              continuation.yield(.metrics(metrics(
                startedAt: startedAt, firstTokenAt: firstTokenAt, usage: usage)))
            case .completed(let completedUsage):
              usage = completedUsage
              continuation.yield(.metrics(metrics(
                startedAt: startedAt, firstTokenAt: firstTokenAt, usage: usage)))
            }
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func metrics(
    startedAt: Date, firstTokenAt: Date?, usage: ChatUsage?
  ) -> ChatUsageMetrics {
    let firstTokenSeconds = firstTokenAt.map { max($0.timeIntervalSince(startedAt), 0) }
    let tokensPerSecond: Double?
    if let completionTokens = usage?.completionTokens, let firstTokenAt {
      let elapsed = max(now().timeIntervalSince(firstTokenAt), 0.001)
      tokensPerSecond = Double(completionTokens) / elapsed
    } else {
      tokensPerSecond = nil
    }
    return .init(
      timeToFirstToken: firstTokenSeconds, tokensPerSecond: tokensPerSecond, usage: usage)
  }
}

enum StudioReadiness: Equatable, Sendable {
  case checking
  case ready
  case unavailable
  case stopped
  case unhealthy
}
