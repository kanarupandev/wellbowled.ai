import XCTest
@testable import wellBowled

final class DeliveryBatchPlannerTests: XCTestCase {

    func testSchedulesRollingSegmentsWithConfiguredOverlap() {
        let windows = DeliveryBatchPlanner.scheduleSegments(
            totalDuration: 225,
            segmentDuration: 60,
            segmentOverlap: 5
        )

        XCTAssertEqual(windows.count, 4)
        XCTAssertEqual(windows[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(windows[0].end, 60, accuracy: 0.0001)
        XCTAssertEqual(windows[1].start, 55, accuracy: 0.0001)
        XCTAssertEqual(windows[1].end, 115, accuracy: 0.0001)
        XCTAssertEqual(windows[2].start, 110, accuracy: 0.0001)
        XCTAssertEqual(windows[2].end, 170, accuracy: 0.0001)
        XCTAssertEqual(windows[3].start, 165, accuracy: 0.0001)
        XCTAssertEqual(windows[3].end, 225, accuracy: 0.0001)
    }

    func testSchedulesSingleSegmentWhenVideoIsShorterThanSegmentDuration() {
        let windows = DeliveryBatchPlanner.scheduleSegments(
            totalDuration: 37,
            segmentDuration: 60,
            segmentOverlap: 5
        )

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(windows[0].end, 37, accuracy: 0.0001)
    }

    func testMergeCandidatesPromotesHybridSourceAndHigherConfidence() {
        let merged = DeliveryBatchPlanner.mergeCandidates(
            candidates: [
                DeliveryTimestampCandidate(timestamp: 10.0, confidence: 0.72, source: .live),
                DeliveryTimestampCandidate(timestamp: 10.35, confidence: 0.91, source: .gemini)
            ],
            dedupeWindow: 0.6,
            sessionDuration: 120
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].source, .hybrid)
        XCTAssertEqual(merged[0].timestamp, 10.35, accuracy: 0.0001)
        XCTAssertGreaterThan(merged[0].confidence, 0.91)
    }

    func testMergeCandidatesUsesEarlierTimestampWhenConfidenceTies() {
        let merged = DeliveryBatchPlanner.mergeCandidates(
            candidates: [
                DeliveryTimestampCandidate(timestamp: 42.4, confidence: 0.8, source: .gemini),
                DeliveryTimestampCandidate(timestamp: 42.1, confidence: 0.8, source: .gemini)
            ],
            dedupeWindow: 0.6,
            sessionDuration: 120
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].timestamp, 42.1, accuracy: 0.0001)
        XCTAssertEqual(merged[0].source, .gemini)
    }

    func testMergeCandidatesClampsIntoSessionDurationRange() {
        let merged = DeliveryBatchPlanner.mergeCandidates(
            candidates: [
                DeliveryTimestampCandidate(timestamp: -3.2, confidence: 0.9, source: .gemini),
                DeliveryTimestampCandidate(timestamp: 45.0, confidence: 0.7, source: .live)
            ],
            dedupeWindow: 0.6,
            sessionDuration: 30
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].timestamp, 0, accuracy: 0.0001)
        XCTAssertEqual(merged[1].timestamp, 30, accuracy: 0.0001)
    }
}
