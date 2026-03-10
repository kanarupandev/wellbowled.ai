import XCTest
@testable import wellBowled

final class GeminiSegmentDeliveryParsingTests: XCTestCase {

    func testParseSegmentDetectionsSupportsMixedNumericPayloads() throws {
        let text = """
        {
          "deliveries": [
            2.4,
            { "release_time_sec": "8.1", "confidence": "0.9" },
            { "time_sec": 11, "confidence": 0.7 },
            { "release_timestamp": 14.2 }
          ]
        }
        """

        let parsed = try GeminiAnalysisService.parseSegmentDeliveryDetections(
            fromCandidateText: text,
            segmentDuration: 12
        )

        XCTAssertEqual(parsed.count, 4)
        assertDoublesEqual(parsed.map(\.localTimestamp), [2.4, 8.1, 11.0, 12.0])
        assertDoublesEqual(parsed.map(\.confidence), [0.5, 0.9, 0.7, 0.5])
    }

    func testParseSegmentDetectionsSupportsReleaseTimesArrayFallback() throws {
        let text = """
        {
          "release_times_sec": [ "1.0", 3, 5.5 ]
        }
        """

        let parsed = try GeminiAnalysisService.parseSegmentDeliveryDetections(
            fromCandidateText: text,
            segmentDuration: 10
        )

        XCTAssertEqual(parsed.count, 3)
        assertDoublesEqual(parsed.map(\.localTimestamp), [1.0, 3.0, 5.5])
        assertDoublesEqual(parsed.map(\.confidence), [0.5, 0.5, 0.5])
    }

    func testParseSegmentDetectionsClampsTimestampAndConfidenceRange() throws {
        let text = """
        ```json
        {
          "deliveries": [
            { "timestamp": -2, "confidence": 3.0 },
            { "timestamp": 20, "confidence": -1.0 }
          ]
        }
        ```
        """

        let parsed = try GeminiAnalysisService.parseSegmentDeliveryDetections(
            fromCandidateText: text,
            segmentDuration: 10
        )

        XCTAssertEqual(parsed.count, 2)
        assertDoublesEqual(parsed.map(\.localTimestamp), [0.0, 10.0])
        assertDoublesEqual(parsed.map(\.confidence), [1.0, 0.0])
    }

    func testParseSegmentDetectionsThrowsOnInvalidJSON() {
        XCTAssertThrowsError(
            try GeminiAnalysisService.parseSegmentDeliveryDetections(
                fromCandidateText: "not-json",
                segmentDuration: 10
            )
        )
    }

    private func assertDoublesEqual(
        _ actual: [Double],
        _ expected: [Double],
        accuracy: Double = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: accuracy, file: file, line: line)
        }
    }
}
