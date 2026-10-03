import XCTest
@testable import LocalAIController

@MainActor
final class MemoryMonitorTimelineTests: XCTestCase {
    func testCaptureKeepsChartTimelineStrictlyIncreasingAfterModalPause() {
        let monitor = MemoryMonitor(probe: ModalPauseMemoryProbe())

        monitor.capture(at: Date(timeIntervalSince1970: 10), servicePIDs: [:])
        monitor.capture(at: Date(timeIntervalSince1970: 12), servicePIDs: [:])
        monitor.capture(at: Date(timeIntervalSince1970: 11), servicePIDs: [:])

        let timestamps = monitor.samples.map(\.timestamp)
        XCTAssertEqual(timestamps.count, 3)
        XCTAssertTrue(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(timestamps.last?.timeIntervalSince1970 ?? 0, 12.001, accuracy: 0.0001)
    }
}

@MainActor
private final class ModalPauseMemoryProbe: MemoryProbing {
    func systemMemory() -> SystemMemoryReading? {
        .init(usedBytes: 1, totalBytes: 2)
    }

    func processTreePhysicalFootprint(rootPID: Int32) -> UInt64? { nil }
}
