import XCTest
@testable import LocalAIController

final class MemoryChartTimelineTests: XCTestCase {
    func testTimelineKeepsStableSegmentsWhenServicesBecomeMeasured() {
        let samples = [
            MemorySample(
                timestamp: Date(timeIntervalSince1970: 1),
                systemUsedBytes: 20,
                systemTotalBytes: 32,
                serviceBytes: [:]
            ),
            MemorySample(
                timestamp: Date(timeIntervalSince1970: 2),
                systemUsedBytes: 24,
                systemTotalBytes: 32,
                serviceBytes: [.embeddings: 3, .llamaChat: 8]
            )
        ]

        let timeline = MemoryChartTimeline.samples(from: samples)

        XCTAssertEqual(timeline.map { $0.segments.map(\.id) }, [
            ["llamaChat", "autocomplete", "embeddings", "other"],
            ["llamaChat", "autocomplete", "embeddings", "other"]
        ])
        XCTAssertEqual(timeline[0].segments.map(\.bytes), [0, 0, 0, 20])
        XCTAssertEqual(timeline[1].segments.map(\.bytes), [8, 0, 3, 13])
        XCTAssertEqual(timeline[0].segments.map(\.isMeasured), [false, false, false, true])
        XCTAssertEqual(timeline[1].segments.map(\.isMeasured), [true, false, true, true])
        XCTAssertEqual(timeline[1].segments.map(\.endBytes).last, 24)
        XCTAssertEqual(timeline.map(\.continuitySegment), [0, 0])
    }

    func testTimelineSplitsStableSeriesAfterGap() {
        let samples = [
            sample(at: 1),
            sample(at: 2),
            sample(at: 20)
        ]

        let timeline = MemoryChartTimeline.samples(from: samples)

        XCTAssertEqual(timeline.map(\.continuitySegment), [0, 0, 1])
        XCTAssertEqual(timeline[0].segments.map(\.id), timeline[2].segments.map(\.id))
    }

    func testChartTimelineConnectsAcrossStartAllPopupGap() {
        let samples = [sample(at: 1), sample(at: 2), sample(at: 20)]

        let timeline = MemoryChartTimeline.samples(from: samples, maximumGap: .infinity)

        XCTAssertEqual(timeline.map(\.continuitySegment), [0, 0, 0])
    }

    private func sample(at timestamp: TimeInterval) -> MemorySample {
        MemorySample(
            timestamp: Date(timeIntervalSince1970: timestamp),
            systemUsedBytes: 0,
            systemTotalBytes: 1,
            serviceBytes: [:]
        )
    }
}
