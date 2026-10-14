import XCTest

@testable import Mochi

final class ChatModelTests: XCTestCase {
  func test_clientExport_usesServiceEndpointAndEscapesShellValues() throws {
    let service = ChatServiceOption(
      serviceID: .llamaChat, name: "Chat", modelName: "Qwen local",
      endpoint: URL(string: "http://127.0.0.1:11437/v1"), state: .running,
      securitySummary: "available only on this Mac")

    let export = try XCTUnwrap(ClientConfigurationExportBuilder.make(service: service))

    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(export.json.utf8)) as? [String: String])
    XCTAssertEqual(json["base_url"], "http://127.0.0.1:11437/v1")
    XCTAssertTrue(export.json.contains("Qwen local"))
    XCTAssertTrue(export.shell.contains("OPENAI_BASE_URL='http://127.0.0.1:11437/v1'"))
    XCTAssertTrue(export.warning.contains("available only on this Mac"))
  }

  func test_chatConversation_decodesLegacyOptionalDefaultsThroughCurrentShape() throws {
    let now = Date(timeIntervalSince1970: 100)
    let conversation = ChatConversation(
      title: "Hello", messages: [.init(role: .user, content: "Hi", createdAt: now)],
      serviceID: .llamaChat, modelName: "local", createdAt: now, updatedAt: now)

    let data = try JSONEncoder().encode(conversation)
    let decoded = try JSONDecoder().decode(ChatConversation.self, from: data)

    XCTAssertEqual(decoded, conversation)
    XCTAssertEqual(decoded.messages.first?.role, .user)
  }
}
