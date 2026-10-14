import Foundation

struct ClientConfigurationExport: Equatable, Sendable {
  let json: String
  let shell: String
  let warning: String
}

enum ClientConfigurationExportBuilder {
  static func make(
    service: ChatServiceOption, apiKey: String = "not-needed"
  ) -> ClientConfigurationExport? {
    guard let endpoint = service.endpoint else { return nil }
    let baseURL = endpoint.absoluteString
    let jsonObject: [String: String] = [
      "base_url": baseURL,
      "model": service.modelName,
      "api_key": apiKey,
    ]
    guard let data = try? JSONSerialization.data(
      withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else { return nil }
    let shell = "export OPENAI_BASE_URL=\(shellQuote(baseURL))\n"
      + "export OPENAI_API_KEY=\(shellQuote(apiKey))\n"
      + "export OPENAI_MODEL=\(shellQuote(service.modelName))"
    return .init(
      json: json, shell: shell,
      warning: "This endpoint is \(service.securitySummary). Use it only with trusted clients."
    )
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
