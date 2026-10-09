import Foundation

struct MemoryChartSegment: Identifiable, Equatable, Sendable {
  let id: String
  let seriesID: String
  let serviceID: ServiceID?
  let isMeasured: Bool
  let bytes: UInt64
  let startBytes: UInt64
  let endBytes: UInt64
}

struct MemoryChartSample: Identifiable, Equatable, Sendable {
  let timestamp: Date
  let totalSystemUsedBytes: UInt64
  let continuitySegment: Int
  let segments: [MemoryChartSegment]

  var id: Date { timestamp }
}

enum MemoryChartTimeline {
  static func samples(
    from samples: [MemorySample],
    maximumGap: TimeInterval = MemoryTimeline.maximumContiguousGap
  ) -> [MemoryChartSample] {
    let continuitySegments = MemoryTimeline.segments(samples: samples, maximumGap: maximumGap)
    var seriesGenerations: [String: Int] = [:]
    var previouslyMeasured: [String: Bool] = [:]
    var previousContinuitySegments: [String: Int] = [:]

    return samples.enumerated().map { index, sample in
      let continuitySegment = continuitySegments[index]
      return MemoryChartSample(
        timestamp: sample.timestamp,
        totalSystemUsedBytes: sample.systemUsedBytes,
        continuitySegment: continuitySegment,
        segments: segments(
          for: sample,
          continuitySegment: continuitySegment,
          seriesGenerations: &seriesGenerations,
          previouslyMeasured: &previouslyMeasured,
          previousContinuitySegments: &previousContinuitySegments
        )
      )
    }
  }

  static func segments(for sample: MemorySample) -> [MemoryChartSegment] {
    var seriesGenerations: [String: Int] = [:]
    var previouslyMeasured: [String: Bool] = [:]
    var previousContinuitySegments: [String: Int] = [:]
    return segments(
      for: sample,
      continuitySegment: 0,
      seriesGenerations: &seriesGenerations,
      previouslyMeasured: &previouslyMeasured,
      previousContinuitySegments: &previousContinuitySegments
    )
  }

  private static func segments(
    for sample: MemorySample,
    continuitySegment: Int,
    seriesGenerations: inout [String: Int],
    previouslyMeasured: inout [String: Bool],
    previousContinuitySegments: inout [String: Int]
  ) -> [MemoryChartSegment] {
    var offset: UInt64 = 0
    var result = ServiceID.allCases.map { id in
      let reading = sample.serviceReadings[id]
      let bytes = reading?.bytes ?? 0
      let isMeasured = reading?.bytes != nil
      let seriesID = nextSeriesID(
        for: id.rawValue,
        isMeasured: isMeasured,
        continuitySegment: continuitySegment,
        generations: &seriesGenerations,
        previouslyMeasured: &previouslyMeasured,
        previousContinuitySegments: &previousContinuitySegments
      )
      let segment = chartSegment(
        id: id.rawValue, seriesID: seriesID, serviceID: id,
        isMeasured: isMeasured, bytes: bytes, start: offset
      )
      offset = segment.endBytes
      return segment
    }
    let other = chartSegment(
      id: "other",
      seriesID: nextSeriesID(
        for: "other", isMeasured: true, continuitySegment: continuitySegment,
        generations: &seriesGenerations, previouslyMeasured: &previouslyMeasured,
        previousContinuitySegments: &previousContinuitySegments
      ),
      serviceID: nil, isMeasured: true, bytes: sample.otherSystemUsageBytes, start: offset
    )
    result.append(other)
    return result
  }

  private static func nextSeriesID(
    for id: String,
    isMeasured: Bool,
    continuitySegment: Int,
    generations: inout [String: Int],
    previouslyMeasured: inout [String: Bool],
    previousContinuitySegments: inout [String: Int]
  ) -> String {
    let wasMeasured = previouslyMeasured[id] ?? false
    let previousContinuity = previousContinuitySegments[id]
    if isMeasured && (!wasMeasured || previousContinuity != continuitySegment) {
      generations[id] = (generations[id] ?? 0) + 1
    }
    previouslyMeasured[id] = isMeasured
    previousContinuitySegments[id] = continuitySegment
    return "\(id)-\(continuitySegment)-\(generations[id] ?? 0)"
  }

  private static func chartSegment(
    id: String,
    seriesID: String,
    serviceID: ServiceID?,
    isMeasured: Bool,
    bytes: UInt64,
    start: UInt64
  ) -> MemoryChartSegment {
    let (end, overflow) = start.addingReportingOverflow(bytes)
    return MemoryChartSegment(
      id: id, seriesID: seriesID, serviceID: serviceID, isMeasured: isMeasured,
      bytes: bytes, startBytes: start, endBytes: overflow ? .max : end
    )
  }
}
