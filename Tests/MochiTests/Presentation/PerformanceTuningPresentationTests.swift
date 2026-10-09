import XCTest
@testable import Mochi

final class PerformanceTuningPresentationTests: XCTestCase {
    func testRecommendationCardsUseBeginnerNamesAndDetectMappedPresets() {
        XCTAssertEqual(BeginnerPerformanceProfile.fast.cardTitle, "Faster")
        XCTAssertEqual(BeginnerPerformanceProfile.fast.title, "Fast")

        let baseline = ModelSettingsProfile.defaults(runtime: .llamaCpp, role: .chat).llama!
        for profile in BeginnerPerformanceProfile.allCases {
            let mapped = PerformancePresetMapper.llama(baseline, preset: profile.preset, baselineContext: baseline.contextSize)
            XCTAssertEqual(
                PerformanceTuningPresentation.activeProfile(for: mapped, role: .chat, baselineContext: baseline.contextSize),
                profile
            )
        }
    }

    func testResponseLengthUpdatesChatOutputOnly() {
        var generation = GenerationProfile.balanced
        generation.autocompleteOutputLimit = 128

        PerformanceTuningPresentation.setResponseValue(2_048, on: &generation, role: .chat)

        XCTAssertEqual(generation.maximumOutputTokens, 2_048)
        XCTAssertEqual(generation.autocompleteOutputLimit, 128)
    }

    func testResponseLengthUpdatesAutocompleteAndGenerationOutput() {
        var generation = GenerationProfile.autocompleteBalanced

        PerformanceTuningPresentation.setResponseValue(256, on: &generation, role: .coding)

        XCTAssertEqual(generation.maximumOutputTokens, 256)
        XCTAssertEqual(generation.autocompleteOutputLimit, 256)
    }

    func testManualContextChangeMarksProfileCustom() {
        let baseline = ModelSettingsProfile.defaults(runtime: .llamaCpp, role: .chat).llama!.contextSize
        var settings = LlamaModelSettings.defaults(for: .chat)
        settings.contextSize = 8_192

        let profile = PerformanceTuningPresentation.activeProfile(for: settings, role: .chat, baselineContext: baseline)

        XCTAssertEqual(profile, .custom)
    }

    func testMemoryStatusMapsEveryAssessmentSafely() {
        XCTAssertEqual(PerformanceTuningPresentation.memoryStatus(for: .safe).message, "Good to go")
        XCTAssertEqual(PerformanceTuningPresentation.memoryStatus(for: .caution).message, "May use more memory")
        XCTAssertEqual(PerformanceTuningPresentation.memoryStatus(for: .high).message, "Consider a smaller context or model")
        XCTAssertEqual(PerformanceTuningPresentation.memoryStatus(for: .unverified).message, "Memory use is unverified")
    }

    func testPerformanceEditorPresentsBeginnerControlsBeforeAdvancedDisclosure() throws {
        let root = try repositoryRoot()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Mochi/Presentation/PerformanceTuningViews.swift"))

        let beginner = try XCTUnwrap(source.range(of: "BeginnerPerformanceControls"))
        let advanced = try XCTUnwrap(source.range(of: "AdvancedPerformanceTuning"))
        XCTAssertLessThan(beginner.lowerBound, advanced.lowerBound)

        let advancedSource = try String(contentsOf: root.appendingPathComponent("Sources/Mochi/Presentation/PerformanceTuningAdvancedViews.swift"))
        XCTAssertTrue(advancedSource.contains("DisclosureGroup(\"Advanced tuning\")"))
        XCTAssertTrue(advancedSource.contains("Autocomplete limit"))
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) { return candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        throw CocoaError(.fileReadNoPermission)
    }
}
