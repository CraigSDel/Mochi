import XCTest

@testable import Mochi

final class PerformanceSettingHelpTests: XCTestCase {
  func testEveryPerformanceSettingHasCompleteHelp() {
    let catalog = PerformanceSettingHelpCatalog.all

    XCTAssertEqual(Set(catalog.map(\.id)), Set(PerformanceSetting.allCases))
    XCTAssertEqual(catalog.count, PerformanceSetting.allCases.count)
    for help in catalog {
      XCTAssertFalse(help.title.isEmpty)
      XCTAssertFalse(help.tooltip.isEmpty)
      XCTAssertFalse(help.explanation.isEmpty)
      XCTAssertTrue(help.accessibilityLabel.contains(help.title))
    }
  }

  func testGenerationSettingsAreSharedByChatAndAutocomplete() {
    let generation: Set<PerformanceSetting> = [
      .maxOutput, .temperature, .topK, .topP, .repeatPenalty, .autocompleteLimit,
    ]

    XCTAssertTrue(generation.isSubset(of: Set(PerformanceSetting.allCases)))
    XCTAssertEqual(generation.count, 6)
  }

  func testEmbeddingRoleHasNoGenerationOnlySettingsInItsEditorContract() {
    let generation: Set<PerformanceSetting> = [
      .maxOutput, .temperature, .topK, .topP, .repeatPenalty, .autocompleteLimit,
    ]
    let embeddingSettings: Set<PerformanceSetting> = [
      .context, .gpuLayers, .batch, .microBatch, .kvKey, .kvValue, .cacheReuse, .flashAttention,
      .threads, .batchThreads,
    ]

    XCTAssertTrue(embeddingSettings.isDisjoint(with: generation))
  }
}
