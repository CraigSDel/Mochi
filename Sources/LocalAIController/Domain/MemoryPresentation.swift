import Foundation

struct ManagedMemoryChartScale {
    let upperBound: Double
    let unit: String
    private let divisor: Double

    init(samples: [MemorySample]) {
        let maximumBytes = samples.map(\.managedBytes).max() ?? 0
        guard maximumBytes > 0 else {
            divisor = 1_073_741_824
            unit = "GiB"
            upperBound = 1
            return
        }
        let units: [(threshold: UInt64, divisor: Double, label: String)] = [
            (1_073_741_824, 1_073_741_824, "GiB"),
            (1_048_576, 1_048_576, "MiB"),
            (1_024, 1_024, "KiB"),
            (1, 1, "bytes")
        ]
        let selectedUnit = units.first { maximumBytes >= $0.threshold }!
        divisor = selectedUnit.divisor
        unit = selectedUnit.label
        upperBound = Double(maximumBytes) / divisor * 1.1
    }

    func value(for bytes: UInt64) -> Double { Double(bytes) / divisor }
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
