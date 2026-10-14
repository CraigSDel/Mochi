import Foundation

struct ChatHTTPStream: Sendable {
  let statusCode: Int
  let lines: AsyncThrowingStream<String, Error>
}

protocol ChatStreaming: Sendable {
  func stream(for request: URLRequest) async throws -> ChatHTTPStream
}

struct URLSessionChatStreaming: ChatStreaming, Sendable {
  func stream(for request: URLRequest) async throws -> ChatHTTPStream {
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ChatTransportError.invalidResponse
    }
    let lines = AsyncThrowingStream<String, Error> { continuation in
      let task = Task {
        do {
          for try await line in bytes.lines {
            try Task.checkCancellation()
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
    return ChatHTTPStream(statusCode: http.statusCode, lines: lines)
  }
}

struct OpenAICompatibleClient: ChatTransporting, Sendable {
  private let streaming: any ChatStreaming

  init(streaming: any ChatStreaming = URLSessionChatStreaming()) {
    self.streaming = streaming
  }

  func stream(
    request: ChatRequest, endpoint: URL
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let url = endpoint.appendingPathComponent("chat/completions")
          var urlRequest = URLRequest(url: url)
          urlRequest.httpMethod = "POST"
          urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
          urlRequest.httpBody = try JSONEncoder().encode(RequestDTO(request: request))
          let response = try await streaming.stream(for: urlRequest)
          guard (200..<300).contains(response.statusCode) else {
            var body = ""
            for try await line in response.lines { body += line }
            if let message = Self.errorMessage(from: Data(body.utf8)) {
              throw ChatTransportError.serverMessage(message)
            }
            throw ChatTransportError.requestFailed(response.statusCode)
          }
          for try await line in response.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ResponseDTO.self, from: data)
            else { continue }
            if let text = chunk.choices.first?.delta.content, !text.isEmpty {
              continuation.yield(.text(text))
            }
            if let usage = chunk.usage {
              continuation.yield(.completed(usage.domainValue))
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

  private static func errorMessage(from data: Data) -> String? {
    guard let response = try? JSONDecoder().decode(ErrorDTO.self, from: data) else { return nil }
    return response.error.message
  }

  private struct RequestDTO: Encodable {
    let model: String
    let messages: [MessageDTO]
    let temperature: Double
    let topK: Int
    let topP: Double
    let maxTokens: Int
    let stream = true

    init(request: ChatRequest) {
      model = request.model
      messages = request.messages.map(MessageDTO.init)
      temperature = request.generation.temperature
      topK = request.generation.topK
      topP = request.generation.topP
      maxTokens = request.generation.maximumOutputTokens
    }

    enum CodingKeys: String, CodingKey {
      case model, messages, temperature, topK = "top_k", topP = "top_p"
      case maxTokens = "max_tokens", stream
    }
  }

  private struct MessageDTO: Codable {
    let role: String
    let content: String
    init(_ message: ChatMessage) { role = message.role.rawValue; content = message.content }
  }

  private struct ResponseDTO: Decodable {
    let choices: [ChoiceDTO]
    let usage: UsageDTO?
  }

  private struct ChoiceDTO: Decodable {
    let delta: DeltaDTO
  }

  private struct DeltaDTO: Decodable { let content: String? }

  private struct UsageDTO: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
      case promptTokens = "prompt_tokens"
      case completionTokens = "completion_tokens"
      case totalTokens = "total_tokens"
    }

    var domainValue: ChatUsage {
      .init(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens)
    }
  }

  private struct ErrorDTO: Decodable {
    let error: ErrorMessage
    struct ErrorMessage: Decodable { let message: String }
  }
}

struct OpenAICompatibleHealthChecker: ChatServiceHealthChecking, Sendable {
  let fetcher: any HTTPFetching

  func check(endpoint: URL) async -> Bool {
    let response = try? await fetcher.fetch(endpoint.appendingPathComponent("models"), timeout: 5)
    return response?.isSuccess == true
  }
}
