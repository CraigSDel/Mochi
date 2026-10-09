import XCTest

@testable import Mochi

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
      ),
    ]

    let timeline = MemoryChartTimeline.samples(from: samples)

    XCTAssertEqual(
      timeline.map { $0.segments.map(\.id) },
      [
        ["llamaChat", "autocomplete", "embeddings", "other"],
        ["llamaChat", "autocomplete", "embeddings", "other"],
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
      sample(at: 20),
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

  func testTimelineStartsNewSeriesAfterUnavailableReading() {
    let samples = [
      MemorySample(
        timestamp: Date(timeIntervalSince1970: 1),
        systemUsedBytes: 10,
        systemTotalBytes: 32,
        serviceReadings: [.llamaChat: .measured(bytes: 4)]
      ),
      MemorySample(
        timestamp: Date(timeIntervalSince1970: 2),
        systemUsedBytes: 11,
        systemTotalBytes: 32,
        serviceReadings: [.llamaChat: .noOwnedPID(reason: "Stopped")]
      ),
      MemorySample(
        timestamp: Date(timeIntervalSince1970: 3),
        systemUsedBytes: 12,
        systemTotalBytes: 32,
        serviceReadings: [.llamaChat: .measured(bytes: 5)]
      ),
    ]

    let timeline = MemoryChartTimeline.samples(from: samples)
    let series = timeline.map { sample in
      sample.segments.first(where: { $0.id == ServiceID.llamaChat.rawValue })?.seriesID
    }

    XCTAssertNotEqual(series[0], series[2])
  }

  func testTimelineStartsNewSeriesAfterSamplingGap() {
    let timeline = MemoryChartTimeline.samples(from: [sample(at: 1), sample(at: 4)])

    XCTAssertNotEqual(
      timeline[0].segments.first(where: { $0.id == "other" })?.seriesID,
      timeline[1].segments.first(where: { $0.id == "other" })?.seriesID
    )
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
