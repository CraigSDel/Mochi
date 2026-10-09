import Foundation

/// Minimal injectable seam over `URLSession` so provider behaviour (prefilters,
/// ordering, and failure fallbacks) is testable without the network.
protocol HTTPFetching: Sendable {
  func fetch(_ url: URL, timeout: TimeInterval) async throws -> HTTPResponse
}

struct HTTPResponse: Sendable {
  let data: Data
  let statusCode: Int

  var isSuccess: Bool { (200..<300).contains(statusCode) }
}

struct URLSessionFetching: HTTPFetching {
  func fetch(_ url: URL, timeout: TimeInterval) async throws -> HTTPResponse {
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return HTTPResponse(data: data, statusCode: http.statusCode)
  }
}
