import XCTest
@testable import wellBowled

final class RecordingSegmentPlannerTests: XCTestCase {

    func testExistingSegmentsFiltersMissingAndDeduplicatesPreservingOrder() {
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        let missing = URL(fileURLWithPath: "/tmp/missing.mov")

        let result = RecordingSegmentPlanner.existingSegments([a, b, a, missing, b]) { url in
            url != missing
        }

        XCTAssertEqual(result, [a, b])
    }

    func testResolvedRecordingURLPrefersMergedURL() {
        let merged = URL(fileURLWithPath: "/tmp/merged.mov")
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let fallback = URL(fileURLWithPath: "/tmp/fallback.mov")

        let result = RecordingSegmentPlanner.resolvedRecordingURL(
            mergedURL: merged,
            segments: [a],
            fallback: fallback
        )

        XCTAssertEqual(result, merged)
    }

    func testResolvedRecordingURLFallsBackToLastSegmentThenFallback() {
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        let fallback = URL(fileURLWithPath: "/tmp/fallback.mov")

        XCTAssertEqual(
            RecordingSegmentPlanner.resolvedRecordingURL(
                mergedURL: nil,
                segments: [a, b],
                fallback: fallback
            ),
            b
        )
        XCTAssertEqual(
            RecordingSegmentPlanner.resolvedRecordingURL(
                mergedURL: nil,
                segments: [],
                fallback: fallback
            ),
            fallback
        )
    }
}

