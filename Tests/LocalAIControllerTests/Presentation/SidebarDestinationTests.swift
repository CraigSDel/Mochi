// Tests/LocalAIControllerTests/Presentation/SidebarDestinationTests.swift
import XCTest
@testable import LocalAIController

final class SidebarDestinationTests: XCTestCase {
    func testTopLevelDestinationsAreDistinctFromEveryServiceDestination() {
        let recommendations = SidebarDestination.recommendations
        let overview = SidebarDestination.overview
        for serviceID in ServiceID.allCases {
            XCTAssertNotEqual(recommendations, .service(serviceID))
            XCTAssertNotEqual(overview, .service(serviceID))
        }
        XCTAssertNotEqual(overview, recommendations)
    }

    func testEveryServiceHasAUniqueDestination() {
        let destinations = ServiceID.allCases.map(SidebarDestination.service)
        XCTAssertEqual(Set(destinations).count, ServiceID.allCases.count)
    }

    func testOverviewIsTheInitialDestination() {
        XCTAssertEqual(SidebarDestination.initial, .overview)
    }
}
