import XCTest
import Darwin
@testable import LocalAIController

@MainActor
final class MemoryMonitoringTests: XCTestCase {
    func testCaptureMapsSystemAndServiceReadings() {
        let probe = FakeMemoryProbe(systemUsed: 12, systemTotal: 32, footprints: [10: 4, 20: 7])
        let monitor = MemoryMonitor(probe: probe, maximumSampleCount: 10)

        monitor.capture(at: Date(timeIntervalSince1970: 1), servicePIDs: [.llamaChat: 10, .ollama: 20])

        XCTAssertEqual(monitor.currentSample?.systemUsedBytes, 12)
        XCTAssertEqual(monitor.currentSample?.systemTotalBytes, 32)
        XCTAssertEqual(monitor.currentSample?.serviceBytes, [.llamaChat: 4, .ollama: 7])
        XCTAssertEqual(monitor.currentSample?.managedBytes, 11)
    }

    func testRollingBufferKeepsNewestSamples() {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2)
        let monitor = MemoryMonitor(probe: probe, maximumSampleCount: 3)

        for second in 0..<5 {
            monitor.capture(at: Date(timeIntervalSince1970: Double(second)), servicePIDs: [:])
        }

        XCTAssertEqual(monitor.samples.count, 3)
        XCTAssertEqual(monitor.samples.map(\.timestamp.timeIntervalSince1970), [2, 3, 4])
    }

    func testUnavailableAndRestartedServicesDoNotLeaveStaleValues() {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2, footprints: [10: 5])
        let monitor = MemoryMonitor(probe: probe)
        monitor.capture(servicePIDs: [.ollama: 10])

        probe.footprints = [:]
        monitor.capture(servicePIDs: [.ollama: 10])
        XCTAssertNil(monitor.currentSample?.serviceBytes[.ollama])

        probe.footprints = [30: 9]
        monitor.capture(servicePIDs: [.ollama: 30])
        XCTAssertEqual(monitor.currentSample?.serviceBytes[.ollama], 9)
    }

    func testNoOwnedPIDUnavailableFootprintAndMeasuredZeroStayDistinct() {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2, footprints: [10: 0])
        let monitor = MemoryMonitor(probe: probe)

        monitor.capture(at: Date(timeIntervalSince1970: 1), servicePIDs: [.llamaChat: 10, .ollama: 20])

        XCTAssertEqual(monitor.currentSample?.serviceReadings[.llamaChat], .measured(bytes: 0))
        XCTAssertEqual(monitor.currentSample?.serviceReadings[.ollama], .footprintUnavailable(pid: 20))
        XCTAssertEqual(monitor.currentSample?.serviceReadings[.autocomplete], .noOwnedPID(reason: "No validated owned PID"))
        XCTAssertEqual(monitor.currentSample?.managedBytes, 0)
        XCTAssertEqual(MemoryFormatting.managedUsage(monitor.currentSample!), "Partial reading")

        monitor.capture(at: Date(timeIntervalSince1970: 2), servicePIDs: [.llamaChat: 10])
        XCTAssertEqual(monitor.currentSample?.serviceReadings[.llamaChat], .measured(bytes: 0))
        XCTAssertEqual(MemoryFormatting.managedUsage(monitor.currentSample!), "Zero KB")
    }

    func testMissingSystemReadingDoesNotAppendSample() {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2)
        let monitor = MemoryMonitor(probe: probe)
        probe.systemReading = nil

        monitor.capture(servicePIDs: [.llamaChat: 10])

        XCTAssertTrue(monitor.samples.isEmpty)
    }

    func testProcessTreeAggregationIncludesDescendantsOnce() {
        let footprints: [pid_t: UInt64] = [1: 10, 2: 20, 3: 30]
        let children: [pid_t: [pid_t]] = [1: [2, 3], 2: [3], 3: [1]]

        let total = ProcessTreeMemory.aggregate(
            rootPID: 1,
            footprint: { footprints[$0] },
            children: { children[$0] ?? [] }
        )

        XCTAssertEqual(total, 60)
    }

    func testSystemMemoryAccountingExcludesReclaimablePages() {
        let used = SystemMemoryAccounting.usedBytes(
            physicalMemory: 16_000,
            pageSize: 1_000,
            freePages: 2,
            inactivePages: 3,
            speculativePages: 1
        )

        XCTAssertEqual(used, 10_000)
    }

    func testSystemMemoryAccountingStaysWithinPhysicalMemoryOnOverflow() {
        let used = SystemMemoryAccounting.usedBytes(
            physicalMemory: 8_000,
            pageSize: UInt64.max,
            freePages: 1,
            inactivePages: 1,
            speculativePages: 1
        )

        XCTAssertEqual(used, 0)
        XCTAssertLessThanOrEqual(used, 8_000)

        let pageCountOverflowUsed = SystemMemoryAccounting.usedBytes(
            physicalMemory: 8_000,
            pageSize: 1,
            freePages: UInt64.max,
            inactivePages: 1,
            speculativePages: 1
        )

        XCTAssertEqual(pageCountOverflowUsed, 0)
    }

    func testManagedMemoryScaleAddsHeadroomAboveInferenceSpike() {
        let samples = [
            memorySample(managed: 2 * 1_073_741_824),
            memorySample(managed: 8 * 1_073_741_824)
        ]
        let scale = ManagedMemoryChartScale(samples: samples)

        XCTAssertEqual(scale.unit, "GiB")
        XCTAssertEqual(scale.upperBound, 8.8, accuracy: 0.0001)
        XCTAssertEqual(scale.value(for: 8 * 1_073_741_824), 8)
    }

    func testManagedMemoryScaleHandlesEmptyAndVerySmallValues() {
        let emptyScale = ManagedMemoryChartScale(samples: [])
        let smallScale = ManagedMemoryChartScale(samples: [memorySample(managed: 4)])

        XCTAssertEqual(emptyScale.upperBound, 1)
        XCTAssertEqual(emptyScale.unit, "GiB")
        XCTAssertEqual(smallScale.unit, "bytes")
        XCTAssertEqual(smallScale.upperBound, 4.4, accuracy: 0.0001)
    }

    func testFormattingAndLabelsAreComplete() {
        XCTAssertFalse(MemoryFormatting.bytes(1_073_741_824).isEmpty)
        XCTAssertTrue(MemoryFormatting.usage(1, of: 2).contains("/"))
        XCTAssertEqual(MemoryFormatting.managedUsage(memorySample(managed: 0)), "Zero KB")
        XCTAssertEqual(MemoryFormatting.managedUsage(emptyMemorySample()), "No owned process")
        XCTAssertEqual(MemoryFormatting.serviceReadingDetail(.noOwnedPID(reason: "No launch record")), "No launch record")
        XCTAssertEqual(Set(ServiceID.allCases.map(MemoryPresentation.label)).count, ServiceID.allCases.count)
    }

    private func memorySample(managed: UInt64) -> MemorySample {
        MemorySample(
            timestamp: Date(timeIntervalSince1970: 1),
            systemUsedBytes: 0,
            systemTotalBytes: 1,
            serviceBytes: [.llamaChat: managed]
        )
    }

    private func emptyMemorySample() -> MemorySample {
        MemorySample(
            timestamp: Date(timeIntervalSince1970: 1),
            systemUsedBytes: 0,
            systemTotalBytes: 1,
            serviceBytes: [:]
        )
    }
}

@MainActor
private final class FakeMemoryProbe: MemoryProbing {
    var systemReading: SystemMemoryReading?
    var footprints: [Int32: UInt64]

    init(systemUsed: UInt64, systemTotal: UInt64, footprints: [Int32: UInt64] = [:]) {
        systemReading = .init(usedBytes: systemUsed, totalBytes: systemTotal)
        self.footprints = footprints
    }

    func systemMemory() -> SystemMemoryReading? { systemReading }
    func processTreePhysicalFootprint(rootPID: Int32) -> UInt64? { footprints[rootPID] }
}
