import XCTest
@testable import LocalAIController

final class PerformanceBudgetTests: XCTestCase {
    func testBudgetsKeepUnboundedInputsBounded() {
        XCTAssertEqual(PerformanceBudgets.maximumRecommendations, 500)
        XCTAssertEqual(PerformanceBudgets.maximumSearchResults, 100)
        XCTAssertEqual(PerformanceBudgets.maximumServiceLogBytes, 64_000)
        XCTAssertEqual(PerformanceBudgets.maximumMemorySamples, 900)
        XCTAssertEqual(PerformanceBudgets.servicePollingInterval, 5)
    }
}
