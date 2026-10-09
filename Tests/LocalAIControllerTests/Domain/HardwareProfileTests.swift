import XCTest
@testable import LocalAIController

final class HardwareProfileTests: XCTestCase {
    func testParserReadsAppleSiliconSysctlAndProfilerValues() {
        let values = [
            "hw.optional.arm64": "1",
            "hw.memsize": "17179869184",
            "hw.ncpu": "10",
            "hw.perflevel0.physicalcpu": "8",
            "hw.perflevel1.physicalcpu": "2",
            "hw.model": "Mac14,9"
        ]
        let json = #"{"SPHardwareDataType":[{"chip":"Apple M2 Pro","physical_memory":"16 GB"}],"SPDisplaysDataType":[{"spdisplays_total_cores":"16"}]}"#.data(using: .utf8)

        let profile = HardwareProfileParser.parse(sysctl: values, systemProfilerData: json, detectedAt: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(profile.architecture, .appleSilicon)
        XCTAssertEqual(profile.chipName, "Apple M2 Pro")
        XCTAssertEqual(profile.chipFamily, "M2")
        XCTAssertEqual(profile.chipGeneration, 2)
        XCTAssertEqual(profile.physicalMemory, 16 * 1_073_741_824)
        XCTAssertEqual(profile.cpuCoreCount, 10)
        XCTAssertEqual(profile.gpuCoreCount, 16)
        XCTAssertTrue(profile.unavailableFields.isEmpty)
    }

    func testParserKeepsUnknownFieldsExplicit() {
        let profile = HardwareProfileParser.parse(sysctl: ["hw.optional.arm64": "0"], systemProfilerData: nil)

        XCTAssertEqual(profile.architecture, .unknown)
        XCTAssertEqual(profile.physicalMemory, 0)
        XCTAssertTrue(profile.unavailableFields.contains("physical memory"))
        XCTAssertTrue(profile.unavailableFields.contains("CPU cores"))
    }

    func testSafeTuningUsesLowerLimitsForSixteenGigabyteMac() {
        let profile = HardwareProfile(
            architecture: .appleSilicon, modelIdentifier: "Mac", chipName: "Apple M1", chipFamily: "M1", chipGeneration: 1,
            physicalMemory: 16 * 1_073_741_824, cpuCoreCount: 8, performanceCoreCount: 4, efficiencyCoreCount: 4,
            gpuCoreCount: 7, detectedAt: Date(), unavailableFields: []
        )
        let config = ServiceLaunchConfiguration.defaultValue(for: .llamaChat)
        let plan = HardwareTuningPolicy.plan(profile: profile, configurations: [.llamaChat: config], installedModels: [], recommendations: [])

        XCTAssertEqual(plan.configurations[.llamaChat]?.llama?.contextSize, 8_192)
        XCTAssertEqual(plan.configurations[.llamaChat]?.llama?.batchSize, 256)
        XCTAssertEqual(plan.configurations[.llamaChat]?.llama?.ubatchSize, 128)
    }

    func testUnknownMemoryDoesNotChangeConfiguration() {
        let config = ServiceLaunchConfiguration.defaultValue(for: .ollama)
        let plan = HardwareTuningPolicy.plan(profile: .unavailable, configurations: [.ollama: config], installedModels: [], recommendations: [])

        XCTAssertTrue(plan.configurations.isEmpty)
        XCTAssertTrue(plan.notes.first?.contains("no settings were changed") == true)
    }
}
