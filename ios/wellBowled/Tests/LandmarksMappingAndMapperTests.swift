import XCTest
@testable import wellBowled

final class LandmarksMappingAndMapperTests: XCTestCase {

    func testToFramePoseLandmarksMapsFramesAndLandmarks() {
        let data = LandmarksData(
            fps: 30,
            w: 1920,
            h: 1080,
            connections: [[11, 13]],
            frames: [
                FrameLandmarks(
                    t: 1.5,
                    p: "release",
                    l: [BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.25, y: 0.75, v: 0.9, f: "good")]
                )
            ]
        )

        let mapped = data.toFramePoseLandmarks()
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].frameNumber, 0)
        XCTAssertEqual(mapped[0].timestamp, 1.5, accuracy: 0.0001)
        XCTAssertEqual(mapped[0].landmarks.count, 1)
        XCTAssertEqual(mapped[0].landmarks[0].index, 16)
        XCTAssertEqual(mapped[0].landmarks[0].name, "RIGHT_WRIST")
        XCTAssertEqual(mapped[0].landmarks[0].x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(mapped[0].landmarks[0].y, 0.75, accuracy: 0.0001)
    }

    func testToExpertAnalysisUsesFallbackPhaseNameAndLabelSynonyms() {
        let data = LandmarksData(
            fps: 30,
            w: 640,
            h: 480,
            connections: [],
            frames: [
                FrameLandmarks(
                    t: 1.0,
                    p: "   ",
                    l: [
                        BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.2, y: 0.3, v: 0.9, f: "attension"),
                        BackendLandmark(i: 14, n: "RIGHT_ELBOW", x: 0.2, y: 0.3, v: 0.9, f: "injury-risk"),
                        BackendLandmark(i: 12, n: "RIGHT_SHOULDER", x: 0.2, y: 0.3, v: 0.9, f: "good")
                    ]
                )
            ]
        )

        let analysis = data.toExpertAnalysisFromGeminiFeedback()
        XCTAssertNotNil(analysis)
        guard let phase = analysis?.phases.first else { return }

        XCTAssertEqual(phase.phaseName, "delivery_phase")
        XCTAssertEqual(phase.feedback.good, ["RIGHT_SHOULDER"])
        XCTAssertEqual(phase.feedback.slow, ["RIGHT_WRIST"])
        XCTAssertEqual(phase.feedback.injuryRisk, ["RIGHT_ELBOW"])
    }

    func testToExpertAnalysisMergesDuplicatePhaseFramesAndDeduplicatesJoints() {
        let data = LandmarksData(
            fps: 30,
            w: 640,
            h: 480,
            connections: [],
            frames: [
                FrameLandmarks(
                    t: 0.8,
                    p: "release",
                    l: [BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.1, y: 0.2, v: 0.9, f: "slow")]
                ),
                FrameLandmarks(
                    t: 1.4,
                    p: "release",
                    l: [
                        BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.1, y: 0.2, v: 0.9, f: "attention"),
                        BackendLandmark(i: 14, n: "RIGHT_ELBOW", x: 0.1, y: 0.2, v: 0.9, f: "risk")
                    ]
                )
            ]
        )

        let analysis = data.toExpertAnalysisFromGeminiFeedback()
        XCTAssertNotNil(analysis)
        guard let phase = analysis?.phases.first else { return }

        XCTAssertEqual(analysis?.phases.count, 1)
        XCTAssertEqual(phase.phaseName, "release")
        XCTAssertEqual(phase.start, 0.8, accuracy: 0.0001)
        XCTAssertEqual(phase.end, 1.4, accuracy: 0.0001)
        XCTAssertEqual(phase.feedback.slow, ["RIGHT_WRIST"])
        XCTAssertEqual(phase.feedback.injuryRisk, ["RIGHT_ELBOW"])
    }

    func testExpertAnalysisMapperPrioritizesInjuryThenSlowThenGood() {
        let phase = ExpertAnalysis.Phase(
            phaseName: "Release",
            start: 1.0,
            end: 2.0,
            feedback: ExpertAnalysis.Phase.Feedback(
                good: ["RIGHT_WRIST", "RIGHT_SHOULDER"],
                slow: ["RIGHT_WRIST"],
                injuryRisk: ["RIGHT_WRIST"]
            )
        )
        let analysis = ExpertAnalysis(phases: [phase])

        XCTAssertEqual(
            ExpertAnalysisMapper.getJointColor(jointName: "RIGHT_WRIST", expertAnalysis: analysis, timestamp: 1.5),
            "red"
        )
        XCTAssertEqual(
            ExpertAnalysisMapper.getJointColor(jointName: "RIGHT_SHOULDER", expertAnalysis: analysis, timestamp: 1.5),
            "green"
        )
        XCTAssertEqual(
            ExpertAnalysisMapper.getJointColor(jointName: "RIGHT_WRIST", expertAnalysis: analysis, timestamp: 2.5),
            "white"
        )
        XCTAssertEqual(
            ExpertAnalysisMapper.getJointColor(jointName: "RIGHT_WRIST", expertAnalysis: nil, timestamp: 1.5),
            "white"
        )
    }
}
