import XCTest
@testable import LocalAIController

final class OllamaLibraryParserTests: XCTestCase {
    /// Trimmed from the real `https://ollama.com/library?sort=newest` markup:
    /// capability badges, parameter-count badges, and the pull counter that must
    /// not be mistaken for a badge.
    private static let page = """
    <div id="repo"><ul role="list">
    <li class="flex items-baseline border-b py-6">
      <a href="/library/deepseek-v4.1-flash" class="group w-full space-y-5">
        <div title="deepseek-v4.1-flash"><h2><div><span class="group-hover:underline truncate">deepseek-v4.1-flash</span></div></h2></div>
        <div class="flex flex-wrap space-x-2">
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">vision</span>
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">tools</span>
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">thinking</span>
          <span class="inline-flex items-center rounded-md bg-cyan-50 px-2 py-0.5 text-xs">cloud</span>
        </div>
        <p><span class="flex items-center"><span>4,948</span><span class="hidden sm:flex">&nbsp;Pulls</span></span></p>
      </a>
    </li>
    <li class="flex items-baseline border-b py-6">
      <a href="/library/nomic-embed-text-v2-moe" class="group w-full space-y-5">
        <div title="nomic-embed-text-v2-moe"><h2><div><span class="truncate">nomic-embed-text-v2-moe</span></div></h2></div>
        <div class="flex flex-wrap space-x-2">
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">embedding</span>
        </div>
      </a>
    </li>
    <li class="flex items-baseline border-b py-6">
      <a href="/library/gemma4" class="group w-full space-y-5">
        <div title="gemma4"><h2><div><span class="truncate">gemma4</span></div></h2></div>
        <div class="flex flex-wrap space-x-2">
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">vision</span>
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">audio</span>
          <span class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs">cloud</span>
          <span class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs">12b</span>
          <span class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs">26b</span>
        </div>
      </a>
    </li>
    </ul></div>
    """

    func testReadsNamesAndCapabilityBadges() {
        let entries = OllamaLibraryParser.entries(html: Self.page)

        XCTAssertEqual(entries.map(\.name), ["deepseek-v4.1-flash", "nomic-embed-text-v2-moe", "gemma4"])
        XCTAssertEqual(entries[0].badges, ["vision", "tools", "thinking", "cloud"])
        XCTAssertEqual(entries[1].badges, ["embedding"])
        XCTAssertEqual(entries[2].badges, ["vision", "audio", "cloud"])
    }

    func testParameterCountBadgesAreNeverTreatedAsCapabilities() {
        let gemma = OllamaLibraryParser.entries(html: Self.page).last { $0.name == "gemma4" }

        // "12b" and "26b" are parameter counts, not byte sizes or capabilities.
        XCTAssertEqual(gemma?.badges, ["vision", "audio", "cloud"])
    }

    func testUnreadableBlocksAreSkippedInsteadOfFailingThePage() {
        let html = """
        <li class="broken"><span>no anchor at all</span>
          <span class="rounded-md">vision</span>
        </li>
        \(Self.page)
        <li class="unterminated"
        """

        let entries = OllamaLibraryParser.entries(html: html)

        XCTAssertEqual(entries.count, 3)
        XCTAssertFalse(entries.contains { $0.name.isEmpty })
    }

    func testEntryCapIsRespected() {
        let rows = (0..<45).map { "<li><a href=\"/library/model-\($0)\"><span class=\"rounded-md\">tools</span></a></li>" }.joined()
        let entries = OllamaLibraryParser.entries(html: "<ul>\(rows)</ul>")

        XCTAssertEqual(entries.count, OllamaLibraryParser.entryLimit)
        XCTAssertEqual(entries.first?.name, "model-0")
        XCTAssertEqual(entries.last?.name, "model-29")
    }

    func testModelWithoutBadgesKeepsAnEmptyCapabilitySet() {
        let entries = OllamaLibraryParser.entries(html: "<li><a href=\"/library/plainmodel\">plain</a></li>")

        XCTAssertEqual(entries.map(\.name), ["plainmodel"])
        XCTAssertTrue(entries[0].badges.isEmpty)
        XCTAssertFalse(ModelCapability.isMultimodal(badges: entries[0].badges))
        XCTAssertFalse(ModelCapability.isCloudOnly(badges: entries[0].badges))
    }

    func testDuplicateRowsAreNotEmittedTwice() {
        let entries = OllamaLibraryParser.entries(html: Self.page + Self.page)

        XCTAssertEqual(entries.count, 3)
    }
}