// Tests/MochiTests/Presentation/SidebarDestinationTests.swift
import XCTest

@testable import Mochi

final class SidebarDestinationTests: XCTestCase {
  func testTopLevelDestinationsAreDistinctFromEveryServiceDestination() {
    let recommendations = SidebarDestination.recommendations
    let overview = SidebarDestination.overview
    let setup = SidebarDestination.setup
    let settings = SidebarDestination.settings
    for serviceID in ServiceID.allCases {
      XCTAssertNotEqual(recommendations, .service(serviceID))
      XCTAssertNotEqual(overview, .service(serviceID))
      XCTAssertNotEqual(setup, .service(serviceID))
      XCTAssertNotEqual(settings, .service(serviceID))
    }
    XCTAssertNotEqual(overview, recommendations)
    XCTAssertNotEqual(overview, settings)
    XCTAssertNotEqual(overview, setup)
    XCTAssertNotEqual(setup, recommendations)
    XCTAssertNotEqual(setup, settings)
    XCTAssertNotEqual(recommendations, settings)
  }

  func testSetupGuideIsConnectedToTheMainNavigation() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Mochi")
    let mainView = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/MainView.swift"))
    let setupGuide = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/SetupGuideView.swift"))

    XCTAssertTrue(mainView.contains("Label(\"Setup guide\""))
    XCTAssertTrue(mainView.contains("case .setup:"))
    XCTAssertTrue(mainView.contains("SetupGuideView(manager: manager)"))
    XCTAssertTrue(setupGuide.contains("It does not install runtimes"))
    XCTAssertTrue(
      setupGuide.contains("https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md"))
    XCTAssertTrue(setupGuide.contains("git clone https://github.com/ggml-org/llama.cpp"))
    XCTAssertTrue(setupGuide.contains("command -v llama-server"))
    XCTAssertTrue(setupGuide.contains("tailscale up"))
    XCTAssertTrue(setupGuide.contains("LAN mode exposes an unauthenticated API"))
  }

  func testEveryServiceHasAUniqueDestination() {
    let destinations = ServiceID.allCases.map(SidebarDestination.service)
    XCTAssertEqual(Set(destinations).count, ServiceID.allCases.count)
  }

  func testOverviewIsTheInitialDestination() {
    XCTAssertEqual(SidebarDestination.initial, .overview)
  }

  func testSettingsRoutePresentsHardwareAndNetworkControls() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Mochi")
    let mainView = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/MainView.swift"))
    let settingsPage = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/SettingsPages.swift"))

    XCTAssertTrue(mainView.contains("case .settings:"))
    XCTAssertTrue(mainView.contains("MainWindowSettingsView(manager: manager)"))
    XCTAssertTrue(settingsPage.contains("HardwareProfileCard(manager: manager)"))
    XCTAssertTrue(settingsPage.contains("NetworkDiagnosticsView(manager: manager)"))
  }

  func testOverviewRemainsFocusedOnStatusAndUsage() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Mochi")
    let overview = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/OverviewView.swift"))

    XCTAssertTrue(overview.contains("MemoryDashboardView(monitor: memoryMonitor)"))
    XCTAssertTrue(overview.contains("OverviewServiceCard"))
    XCTAssertTrue(overview.contains("attemptStartAll(manager)"))
    XCTAssertTrue(overview.contains("manager.stopAll()"))
    XCTAssertFalse(overview.contains("HardwareProfileCard"))
    XCTAssertFalse(overview.contains("HardwareRecommendationsView"))
    XCTAssertFalse(overview.contains("RecommendationStore"))
    XCTAssertFalse(overview.contains("ModelDownloadCoordinator"))
  }

  func testRecommendationsRemainHardwareBackedWithDownloadActions() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Mochi")
    let recommendations = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/RecommendationsView.swift"))
    let hardwareRecommendations = try String(
      contentsOf: sourceRoot.appendingPathComponent(
        "Presentation/HardwareRecommendationsView.swift"))

    XCTAssertTrue(
      recommendations.contains(
        "HardwareRecommendationsView(manager: manager, store: store, downloads: downloads"))
    XCTAssertTrue(hardwareRecommendations.contains("manager.hardwareProfile"))
    XCTAssertTrue(hardwareRecommendations.contains("downloads.enqueue(catalogModel)"))
  }

  func testServiceConfigurationSectionsFollowExpectedOrder() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Mochi")
    let configuration = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/ServiceConfigurationEditor.swift")
    )
    let serviceDetail = try String(
      contentsOf: sourceRoot.appendingPathComponent("Presentation/ServiceViews.swift"))

    let connection = try XCTUnwrap(configuration.range(of: "SectionHeading(\"Connection\""))
    let model = try XCTUnwrap(configuration.range(of: "SectionHeading(\"Model\""))
    let performance = try XCTUnwrap(
      configuration.range(of: "PerformanceTuningEditor(serviceID: serviceID"))
    let advanced = try XCTUnwrap(configuration.range(of: "DisclosureGroup(\"Advanced\""))
    XCTAssertLessThan(connection.lowerBound, model.lowerBound)
    XCTAssertLessThan(model.lowerBound, performance.lowerBound)
    XCTAssertLessThan(performance.lowerBound, advanced.lowerBound)
    XCTAssertFalse(configuration.contains("DisclosureGroup(\"Custom model\""))
    XCTAssertFalse(configuration.contains("DisclosureGroup(\"Custom model names\""))
    XCTAssertTrue(configuration.contains("Text(\"Custom model\")"))

    let editor = try XCTUnwrap(serviceDetail.range(of: "ServiceConfigurationEditor("))
    let log = try XCTUnwrap(serviceDetail.range(of: "SectionHeading(\"Runtime log\""))
    XCTAssertLessThan(editor.lowerBound, log.lowerBound)
  }
}
