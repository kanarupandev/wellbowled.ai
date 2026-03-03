import XCTest
@testable import wellBowled

final class GeminiFeedbackMappingTests: XCTestCase {

    func testToExpertAnalysisFromGeminiFeedbackMapsJointBuckets() {
        let data = LandmarksData(
            fps: 30,
            w: 640,
            h: 480,
            connections: [],
            frames: [
                FrameLandmarks(
                    t: 1.0,
                    p: "release",
                    l: [
                        BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.4, y: 0.6, v: 0.9, f: "injury_risk"),
                        BackendLandmark(i: 14, n: "RIGHT_ELBOW", x: 0.45, y: 0.5, v: 0.9, f: "slow")
                    ]
                ),
                FrameLandmarks(
                    t: 1.2,
                    p: "release",
                    l: [
                        BackendLandmark(i: 12, n: "RIGHT_SHOULDER", x: 0.5, y: 0.4, v: 0.9, f: "good")
                    ]
                ),
                FrameLandmarks(
                    t: 2.0,
                    p: "follow_through",
                    l: [
                        BackendLandmark(i: 24, n: "RIGHT_HIP", x: 0.52, y: 0.62, v: 0.9, f: "attension")
                    ]
                )
            ]
        )

        let analysis = data.toExpertAnalysisFromGeminiFeedback()
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.phases.count, 2)

        let release = analysis?.phases.first(where: { $0.phaseName == "release" })
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.feedback.injuryRisk, ["RIGHT_WRIST"])
        XCTAssertEqual(release?.feedback.slow, ["RIGHT_ELBOW"])
        XCTAssertEqual(release?.feedback.good, ["RIGHT_SHOULDER"])

        let follow = analysis?.phases.first(where: { $0.phaseName == "follow_through" })
        XCTAssertNotNil(follow)
        XCTAssertEqual(follow?.feedback.slow, ["RIGHT_HIP"])
    }

    func testToExpertAnalysisFromGeminiFeedbackReturnsNilWhenNoLabels() {
        let data = LandmarksData(
            fps: 30,
            w: 640,
            h: 480,
            connections: [],
            frames: [
                FrameLandmarks(
                    t: 0.5,
                    p: "run_up",
                    l: [
                        BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.4, y: 0.6, v: 0.9, f: nil)
                    ]
                )
            ]
        )

        XCTAssertNil(data.toExpertAnalysisFromGeminiFeedback())
    }
}
