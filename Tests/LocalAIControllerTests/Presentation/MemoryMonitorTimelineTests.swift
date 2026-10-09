import XCTest
@testable import LocalAIController

@MainActor
final class MemoryMonitorTimelineTests: XCTestCase {
    func testCaptureKeepsChartTimelineStrictlyIncreasingAfterModalPause() async {
        let monitor = MemoryMonitor(probe: ModalPauseMemoryProbe())

        await monitor.capture(at: Date(timeIntervalSince1970: 10), serviceRoots: [:])
        await monitor.capture(at: Date(timeIntervalSince1970: 12), serviceRoots: [:])
        await monitor.capture(at: Date(timeIntervalSince1970: 11), serviceRoots: [:])

        let timestamps = monitor.samples.map(\.timestamp)
        XCTAssertEqual(timestamps.count, 3)
        XCTAssertTrue(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(timestamps.last?.timeIntervalSince1970 ?? 0, 12.001, accuracy: 0.0001)
    }
}

@MainActor
private final class ModalPauseMemoryProbe: MemoryProbing {
    func systemMemory() async -> SystemMemoryReading? {
        .init(usedBytes: 1, totalBytes: 2)
    }

    func processTreePhysicalFootprint(rootPID: Int32) async -> UInt64? { nil }
}
