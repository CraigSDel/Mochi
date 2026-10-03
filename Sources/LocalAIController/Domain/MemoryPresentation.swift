import Foundation

struct MemoryChartScale {
    let upperBound: Double
    let unit: String
    private let divisor: Double

    init(samples: [MemorySample]) {
        divisor = 1_073_741_824
        unit = "GiB"
        let maximumSystemBytes = samples.map(\.systemUsedBytes).max() ?? 0
        let maximumCompositionBytes = samples.map { sample in
            sample.composition.segments.reduce(UInt64(0)) { total, segment in
                let (sum, overflow) = total.addingReportingOverflow(segment.bytes)
                return overflow ? .max : sum
            }
        }.max() ?? 0
        let maximumBytes = max(maximumSystemBytes, maximumCompositionBytes)
        upperBound = max(1, Double(maximumBytes) / divisor * 1.1)
    }

    func value(for bytes: UInt64) -> Double { Double(bytes) / divisor }
}

struct MemoryCompositionSegment: Identifiable, Equatable, Sendable {
    let id: String
    let serviceID: ServiceID?
    let bytes: UInt64

    var label: String {
        serviceID.map(MemoryPresentation.label) ?? "Other system usage"
    }
}

struct MemoryComposition: Equatable, Sendable {
    let totalSystemUsedBytes: UInt64
    let managedBytes: UInt64
    let otherSystemUsageBytes: UInt64
    let segments: [MemoryCompositionSegment]
    let readingsMayBeIncomplete: Bool
}

struct MemoryChartSegment: Identifiable, Equatable, Sendable {
    let id: String
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
        return samples.enumerated().map { index, sample in
            MemoryChartSample(
                timestamp: sample.timestamp,
                totalSystemUsedBytes: sample.systemUsedBytes,
                continuitySegment: continuitySegments[index],
                segments: segments(for: sample)
            )
        }
    }

    static func segments(for sample: MemorySample) -> [MemoryChartSegment] {
        var offset: UInt64 = 0
        var result = ServiceID.allCases.map { id in
            let reading = sample.serviceReadings[id]
            let bytes = reading?.bytes ?? 0
            let segment = chartSegment(
                id: id.rawValue,
                serviceID: id,
                isMeasured: reading?.bytes != nil,
                bytes: bytes,
                start: offset
            )
            offset = segment.endBytes
            return segment
        }
        let other = chartSegment(
            id: "other",
            serviceID: nil,
            isMeasured: true,
            bytes: sample.otherSystemUsageBytes,
            start: offset
        )
        result.append(other)
        return result
    }

    private static func chartSegment(
        id: String,
        serviceID: ServiceID?,
        isMeasured: Bool,
        bytes: UInt64,
        start: UInt64
    ) -> MemoryChartSegment {
        let (end, overflow) = start.addingReportingOverflow(bytes)
        return MemoryChartSegment(
            id: id,
            serviceID: serviceID,
            isMeasured: isMeasured,
            bytes: bytes,
            startBytes: start,
            endBytes: overflow ? .max : end
        )
    }
}

enum MemoryAccounting {
    static func otherSystemUsage(systemUsedBytes: UInt64, managedBytes: UInt64) -> UInt64 {
        systemUsedBytes >= managedBytes ? systemUsedBytes - managedBytes : 0
    }

    static func composition(for sample: MemorySample) -> MemoryComposition {
        let measured = ServiceID.allCases.compactMap { id -> MemoryCompositionSegment? in
            guard let bytes = sample.serviceReadings[id]?.bytes else { return nil }
            return MemoryCompositionSegment(id: id.rawValue, serviceID: id, bytes: bytes)
        }
        let managedBytes = measured.reduce(UInt64(0)) { total, segment in
            let (sum, overflow) = total.addingReportingOverflow(segment.bytes)
            return overflow ? .max : sum
        }
        let otherBytes = otherSystemUsage(
            systemUsedBytes: sample.systemUsedBytes,
            managedBytes: managedBytes
        )
        let other = MemoryCompositionSegment(id: "other", serviceID: nil, bytes: otherBytes)
        let incomplete = managedBytes > sample.systemUsedBytes || sample.serviceReadings.values.contains {
            if case .footprintUnavailable = $0 { return true }
            return false
        }
        return MemoryComposition(
            totalSystemUsedBytes: sample.systemUsedBytes,
            managedBytes: managedBytes,
            otherSystemUsageBytes: otherBytes,
            segments: measured + [other],
            readingsMayBeIncomplete: incomplete
        )
    }
}

extension MemorySample {
    var composition: MemoryComposition { MemoryAccounting.composition(for: self) }
    var otherSystemUsageBytes: UInt64 { composition.otherSystemUsageBytes }
    var readingsMayBeIncomplete: Bool { composition.readingsMayBeIncomplete }
}

enum MemoryTimeline {
    static let expectedSampleInterval: TimeInterval = 1
    static let maximumContiguousGap = expectedSampleInterval * 2

    static func segments(
        samples: [MemorySample],
        maximumGap: TimeInterval = maximumContiguousGap
    ) -> [Int] {
        guard !samples.isEmpty else { return [] }

        var segment = 0
        var result = [segment]
        for index in samples.indices.dropFirst() {
            let gap = samples[index].timestamp.timeIntervalSince(samples[index - 1].timestamp)
            if gap > maximumGap { segment += 1 }
            result.append(segment)
        }
        return result
    }
}

enum MemoryFormatting {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    static func usage(_ used: UInt64, of total: UInt64) -> String {
        "\(bytes(used)) / \(bytes(total))"
    }

    static func managedUsage(_ sample: MemorySample) -> String {
        let readings = ServiceID.allCases.compactMap { sample.serviceReadings[$0] }
        let measuredCount = readings.filter { $0.bytes != nil }.count
        let unavailableCount = readings.filter {
            if case .footprintUnavailable = $0 { return true }
            return false
        }.count
        if measuredCount == 0 {
            return unavailableCount > 0 ? "Footprint unavailable" : "No owned process"
        }
        if unavailableCount > 0 { return "Partial reading" }
        return bytes(sample.managedBytes)
    }

    static func serviceReading(_ reading: ServiceMemoryReading) -> String {
        switch reading {
        case .noOwnedPID: "No owned PID"
        case .footprintUnavailable: "Footprint unavailable"
        case .measured(let bytes): self.bytes(bytes)
        }
    }

    static func serviceReadingDetail(_ reading: ServiceMemoryReading) -> String {
        switch reading {
        case .noOwnedPID(let reason): reason
        case .footprintUnavailable(let pid): "Physical footprint unavailable for owned PID \(pid)."
        case .measured(let bytes): "Measured process-tree physical footprint: \(self.bytes(bytes))."
        }
    }
}

enum MemoryPresentation {
    static func label(for id: ServiceID) -> String {
        switch id {
        case .llamaChat: "Chat"
        case .autocomplete: "Autocomplete"
        case .embeddings: "Embeddings"
        case .ollama: "Ollama"
        }
    }
}
