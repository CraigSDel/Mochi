import XCTest
import Darwin
import AppKit
@testable import LocalAIController

@MainActor
final class MemoryMonitoringTests: XCTestCase {
    func testCaptureMapsSystemAndServiceReadings() async {
        let probe = FakeMemoryProbe(systemUsed: 12, systemTotal: 32, footprints: [10: 4, 20: 7])
        let monitor = MemoryMonitor(probe: probe, maximumSampleCount: 10)

        await monitor.capture(at: Date(timeIntervalSince1970: 1), serviceRoots: ownedRoots([.llamaChat: 10, .ollama: 20]))

        XCTAssertEqual(monitor.currentSample?.systemUsedBytes, 12)
        XCTAssertEqual(monitor.currentSample?.systemTotalBytes, 32)
        XCTAssertEqual(monitor.currentSample?.serviceBytes, [.llamaChat: 4, .ollama: 7])
        XCTAssertEqual(monitor.currentSample?.managedBytes, 11)
        XCTAssertEqual(monitor.currentSample?.otherSystemUsageBytes, 1)
    }

    func testRollingBufferKeepsNewestSamples() async {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2)
        let monitor = MemoryMonitor(probe: probe, maximumSampleCount: 3)

        for second in 0..<5 {
            await monitor.capture(at: Date(timeIntervalSince1970: Double(second)), serviceRoots: [:])
        }

        XCTAssertEqual(monitor.samples.count, 3)
        XCTAssertEqual(monitor.samples.map(\.timestamp.timeIntervalSince1970), [2, 3, 4])
    }

    func testMemoryTimelineSplitsSamplesAcrossSleepGap() {
        let samples = [
            memorySample(at: 1),
            memorySample(at: 2),
            memorySample(at: 20)
        ]

        XCTAssertEqual(MemoryTimeline.segments(samples: samples), [0, 0, 1])
    }

    func testMemoryTimelineKeepsNormallySpacedSamplesTogether() {
        let samples = [
            memorySample(at: 1),
            memorySample(at: 2),
            memorySample(at: 3)
        ]

        XCTAssertEqual(MemoryTimeline.segments(samples: samples), [0, 0, 0])
    }

    func testWakeCapturesFreshSampleWithoutClearingHistory() async {
        let notificationCenter = NotificationCenter()
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2)
        let monitor = MemoryMonitor(probe: probe, wakeNotificationCenter: notificationCenter)

        await monitor.start(serviceRoots: { [:] })
        probe.systemReading = .init(usedBytes: 2, totalBytes: 2)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(monitor.samples.count, 2)
        XCTAssertEqual(monitor.samples.first?.systemUsedBytes, 1)
        XCTAssertEqual(monitor.samples.last?.systemUsedBytes, 2)
        monitor.stop()
    }

    func testStoppingMonitorRemovesWakeObserver() async {
        let notificationCenter = NotificationCenter()
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2)
        let monitor = MemoryMonitor(probe: probe, wakeNotificationCenter: notificationCenter)

        await monitor.start(serviceRoots: { [:] })
        monitor.stop()
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(monitor.samples.count, 1)
    }

    func testUnavailableAndRestartedServicesDoNotLeaveStaleValues() async {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2, footprints: [10: 5])
        let monitor = MemoryMonitor(probe: probe)
        await monitor.capture(serviceRoots: ownedRoots([.ollama: 10]))

        probe.footprints = [:]
        await monitor.capture(serviceRoots: ownedRoots([.ollama: 10]))
        XCTAssertNil(monitor.currentSample?.serviceBytes[.ollama])

        probe.footprints = [30: 9]
        await monitor.capture(serviceRoots: ownedRoots([.ollama: 30]))
        XCTAssertEqual(monitor.currentSample?.serviceBytes[.ollama], 9)
    }

    func testNoOwnedPIDUnavailableFootprintAndMeasuredZeroStayDistinct() async {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2, footprints: [10: 0])
        let monitor = MemoryMonitor(probe: probe)

        await monitor.capture(at: Date(timeIntervalSince1970: 1), serviceRoots: ownedRoots([.llamaChat: 10, .ollama: 20]))

        XCTAssertEqual(monitor.currentSample?.serviceReadings[.llamaChat], .measured(bytes: 0))
        XCTAssertEqual(monitor.currentSample?.serviceReadings[.ollama], .footprintUnavailable(pid: 20))
        XCTAssertEqual(monitor.currentSample?.serviceReadings[.autocomplete], .noOwnedPID(reason: "No validated owned PID"))
        XCTAssertEqual(monitor.currentSample?.managedBytes, 0)
        XCTAssertEqual(MemoryFormatting.managedUsage(monitor.currentSample!), "Partial reading")

        await monitor.capture(at: Date(timeIntervalSince1970: 2), serviceRoots: ownedRoots([.llamaChat: 10]))
        XCTAssertEqual(monitor.currentSample?.serviceReadings[.llamaChat], .measured(bytes: 0))
        XCTAssertEqual(MemoryFormatting.managedUsage(monitor.currentSample!), "Zero KB")
    }

    func testMissingSystemReadingDoesNotAppendSample() async {
        let probe = FakeMemoryProbe(systemUsed: 1, systemTotal: 2)
        let monitor = MemoryMonitor(probe: probe)
        probe.systemReading = nil

        await monitor.capture(serviceRoots: ownedRoots([.llamaChat: 10]))

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

    func testMemoryScaleUsesReconciledSystemUsedTotal() {
        let samples = [
            memorySample(systemUsed: 2 * 1_073_741_824, managed: 1 * 1_073_741_824),
            memorySample(systemUsed: 8 * 1_073_741_824, managed: 3 * 1_073_741_824)
        ]
        let scale = MemoryChartScale(samples: samples)

        XCTAssertEqual(scale.unit, "GiB")
        XCTAssertEqual(scale.upperBound, 8.8, accuracy: 0.0001)
        XCTAssertEqual(scale.value(for: 8 * 1_073_741_824), 8)
    }

    func testMemoryScaleHandlesEmptyTinyAndLargeValues() {
        let emptyScale = MemoryChartScale(samples: [])
        let tinyScale = MemoryChartScale(samples: [memorySample(systemUsed: 4, managed: 4)])
        let largeScale = MemoryChartScale(samples: [memorySample(systemUsed: 64 * 1_073_741_824, managed: 1)])

        XCTAssertEqual(emptyScale.upperBound, 1)
        XCTAssertEqual(emptyScale.unit, "GiB")
        XCTAssertEqual(tinyScale.upperBound, 1)
        XCTAssertEqual(largeScale.upperBound, 70.4, accuracy: 0.0001)
    }

    func testMemoryAccountingReconcilesMeasuredServicesWithOtherUsage() {
        let sample = MemorySample(
            timestamp: .now,
            systemUsedBytes: 20,
            systemTotalBytes: 32,
            serviceReadings: [.llamaChat: .measured(bytes: 7), .ollama: .measured(bytes: 5)]
        )

        XCTAssertEqual(MemoryAccounting.otherSystemUsage(systemUsedBytes: 20, managedBytes: 12), 8)
        XCTAssertEqual(sample.composition.otherSystemUsageBytes, 8)
        XCTAssertEqual(sample.composition.segments.map(\.bytes).reduce(0, +), sample.systemUsedBytes)
    }

    func testMemoryAccountingClampsResidualWhenManagedExceedsSystemUsage() {
        let sample = MemorySample(
            timestamp: .now,
            systemUsedBytes: 10,
            systemTotalBytes: 32,
            serviceReadings: [.llamaChat: .measured(bytes: 12)]
        )

        XCTAssertEqual(sample.otherSystemUsageBytes, 0)
        XCTAssertTrue(sample.readingsMayBeIncomplete)
        XCTAssertEqual(sample.composition.segments.map(\.bytes).reduce(0, +), 12)
        XCTAssertFalse(sample.composition.segments.contains { $0.bytes > 0 && $0.serviceID == nil })
    }

    func testMemoryAccountingPreservesUnavailableServiceAndMarksIncomplete() {
        let sample = MemorySample(
            timestamp: .now,
            systemUsedBytes: 10,
            systemTotalBytes: 32,
            serviceReadings: [
                .llamaChat: .measured(bytes: 4),
                .ollama: .footprintUnavailable(pid: 42),
                .embeddings: .noOwnedPID(reason: "Stopped")
            ]
        )

        XCTAssertTrue(sample.readingsMayBeIncomplete)
        XCTAssertEqual(sample.composition.managedBytes, 4)
        XCTAssertEqual(sample.otherSystemUsageBytes, 6)
        XCTAssertNil(sample.composition.segments.first { $0.serviceID == .ollama })
        XCTAssertEqual(sample.composition.segments.map(\.bytes).reduce(0, +), sample.systemUsedBytes)
    }

    func testFormattingAndLabelsAreComplete() {
        XCTAssertFalse(MemoryFormatting.bytes(1_073_741_824).isEmpty)
        XCTAssertTrue(MemoryFormatting.usage(1, of: 2).contains("/"))
        XCTAssertEqual(MemoryFormatting.managedUsage(memorySample(managed: 0)), "Zero KB")
        XCTAssertEqual(MemoryFormatting.managedUsage(emptyMemorySample()), "No owned process")
        XCTAssertEqual(MemoryFormatting.serviceReadingDetail(.noOwnedPID(reason: "No launch record")), "No launch record")
        XCTAssertEqual(Set(ServiceID.allCases.map(MemoryPresentation.label)).count, ServiceID.allCases.count)
    }

    private func memorySample(systemUsed: UInt64, managed: UInt64) -> MemorySample {
        MemorySample(
            timestamp: Date(timeIntervalSince1970: 1),
            systemUsedBytes: systemUsed,
            systemTotalBytes: 1,
            serviceBytes: [.llamaChat: managed]
        )
    }

    private func memorySample(managed: UInt64) -> MemorySample {
        memorySample(systemUsed: managed, managed: managed)
    }

    private func memorySample(at timestamp: TimeInterval) -> MemorySample {
        MemorySample(
            timestamp: Date(timeIntervalSince1970: timestamp),
            systemUsedBytes: 0,
            systemTotalBytes: 1,
            serviceBytes: [:]
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

    private func ownedRoots(_ pids: [ServiceID: Int32]) -> [ServiceID: ManagedProcessRoot] {
        Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { id in
            (id, pids[id].map(ManagedProcessRoot.owned) ?? .noOwnedPID(reason: "No validated owned PID"))
        })
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

    func systemMemory() async -> SystemMemoryReading? { systemReading }
    func processTreePhysicalFootprint(rootPID: Int32) async -> UInt64? { footprints[rootPID] }
}
