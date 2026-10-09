import XCTest
@testable import Mochi

final class MemoryChartScaleTests: XCTestCase {
    func testScaleIncludesIncompleteCompositionAboveSystemUsage() {
        let sample = MemorySample(
            timestamp: .now,
            systemUsedBytes: 10 * 1_073_741_824,
            systemTotalBytes: 32 * 1_073_741_824,
            serviceReadings: [.llamaChat: .measured(bytes: 12 * 1_073_741_824)]
        )

        let scale = MemoryChartScale(samples: [sample])

        XCTAssertEqual(scale.upperBound, 13.2, accuracy: 0.0001)
    }
}
