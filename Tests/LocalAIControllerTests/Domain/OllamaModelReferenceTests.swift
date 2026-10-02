import XCTest
@testable import LocalAIController

final class OllamaModelReferenceTests: XCTestCase {
    func testTaglessAndDefaultTaggedNamesAreTheSameReference() {
        XCTAssertEqual(OllamaModelReference.canonical("llava"), "llava:latest")
        XCTAssertEqual(OllamaModelReference.key("llava"), OllamaModelReference.key("llava:latest"))
        XCTAssertEqual(OllamaModelReference.key("llava"), OllamaModelReference.key("LLAVA:Latest"))
        XCTAssertEqual(OllamaModelReference.canonical("  qwen3  "), "qwen3:latest")
    }

    func testNamespaceIsNeverSplitOnAColon() {
        XCTAssertEqual(OllamaModelReference.canonical("acme/model"), "acme/model:latest")
        XCTAssertEqual(OllamaModelReference.canonical("acme/model:8b"), "acme/model:8b")
        XCTAssertNotEqual(OllamaModelReference.key("acme/model:8b"), OllamaModelReference.key("acme/model:latest"))
    }

    func testDifferentTagsRemainDifferentModels() {
        XCTAssertNotEqual(OllamaModelReference.key("qwen3:8b"), OllamaModelReference.key("qwen3"))
        XCTAssertEqual(OllamaModelReference.canonical("qwen3:8b"), "qwen3:8b")
    }

    func testEmptyInputDoesNotProduceAWildcardKey() {
        XCTAssertEqual(OllamaModelReference.canonical(""), "")
        XCTAssertNotEqual(OllamaModelReference.key(""), OllamaModelReference.key("llava"))
    }
}