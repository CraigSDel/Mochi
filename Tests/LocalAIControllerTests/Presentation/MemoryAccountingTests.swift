import XCTest
@testable import LocalAIController

@MainActor
final class MemoryAccountingTests: XCTestCase {
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
    }}

