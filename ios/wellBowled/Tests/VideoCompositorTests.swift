import XCTest
@testable import wellBowled

final class VideoCompositorTests: XCTestCase {

    // MARK: - Frame Matching (Binary Search)

    func testFindClosestFrame_emptyArray_returnsNil() {
        let result = VideoCompositor.findClosestFrame(for: 1.0, in: [])
        XCTAssertNil(result)
    }

    func testFindClosestFrame_singleFrame_returnsThatFrame() {
        let frames = [makeFrame(timestamp: 0.5, frameNumber: 0)]
        let result = VideoCompositor.findClosestFrame(for: 1.0, in: frames)
        XCTAssertEqual(result?.timestamp, 0.5)
    }

    func testFindClosestFrame_exactMatch() {
        let frames = [
            makeFrame(timestamp: 0.0, frameNumber: 0),
            makeFrame(timestamp: 0.5, frameNumber: 1),
            makeFrame(timestamp: 1.0, frameNumber: 2),
            makeFrame(timestamp: 1.5, frameNumber: 3)
        ]
        let result = VideoCompositor.findClosestFrame(for: 1.0, in: frames)
        XCTAssertEqual(result?.frameNumber, 2)
    }

    func testFindClosestFrame_betweenFrames_closerToLeft() {
        let frames = [
            makeFrame(timestamp: 0.0, frameNumber: 0),
            makeFrame(timestamp: 1.0, frameNumber: 1),
            makeFrame(timestamp: 2.0, frameNumber: 2)
        ]
        // 0.3 is closer to 0.0 than to 1.0
        let result = VideoCompositor.findClosestFrame(for: 0.3, in: frames)
        XCTAssertEqual(result?.frameNumber, 0)
    }

    func testFindClosestFrame_betweenFrames_closerToRight() {
        let frames = [
            makeFrame(timestamp: 0.0, frameNumber: 0),
            makeFrame(timestamp: 1.0, frameNumber: 1),
            makeFrame(timestamp: 2.0, frameNumber: 2)
        ]
        // 0.8 is closer to 1.0 than to 0.0
        let result = VideoCompositor.findClosestFrame(for: 0.8, in: frames)
        XCTAssertEqual(result?.frameNumber, 1)
    }

    func testFindClosestFrame_beforeFirstFrame() {
        let frames = [
            makeFrame(timestamp: 1.0, frameNumber: 0),
            makeFrame(timestamp: 2.0, frameNumber: 1)
        ]
        let result = VideoCompositor.findClosestFrame(for: 0.0, in: frames)
        XCTAssertEqual(result?.frameNumber, 0)
    }

    func testFindClosestFrame_afterLastFrame() {
        let frames = [
            makeFrame(timestamp: 1.0, frameNumber: 0),
            makeFrame(timestamp: 2.0, frameNumber: 1)
        ]
        let result = VideoCompositor.findClosestFrame(for: 10.0, in: frames)
        XCTAssertEqual(result?.frameNumber, 1)
    }

    // MARK: - Color Conversion

    func testCgColor_noAnalysis_returnsWhite() {
        let color = VideoCompositor.cgColor(for: "LEFT_SHOULDER", timestamp: 0.5, expertAnalysis: nil)
        XCTAssertEqual(color, UIColor.white.cgColor)
    }

    func testCgColor_goodJoint_returnsGreen() {
        let analysis = ExpertAnalysis(phases: [
            ExpertAnalysis.Phase(
                phaseName: "Delivery",
                start: 0.0,
                end: 1.0,
                feedback: ExpertAnalysis.Phase.Feedback(
                    good: ["LEFT_SHOULDER"],
                    slow: [],
                    injuryRisk: []
                )
            )
        ])
        let color = VideoCompositor.cgColor(for: "LEFT_SHOULDER", timestamp: 0.5, expertAnalysis: analysis)
        // Should be goodCG (green)
        assertCGColorApprox(color, UIColor(red: 0.125, green: 0.788, blue: 0.592, alpha: 1.0).cgColor)
    }

    func testCgColor_slowJoint_returnsAttention() {
        let analysis = ExpertAnalysis(phases: [
            ExpertAnalysis.Phase(
                phaseName: "Loading",
                start: 0.0,
                end: 1.0,
                feedback: ExpertAnalysis.Phase.Feedback(
                    good: [],
                    slow: ["RIGHT_ELBOW"],
                    injuryRisk: []
                )
            )
        ])
        let color = VideoCompositor.cgColor(for: "RIGHT_ELBOW", timestamp: 0.5, expertAnalysis: analysis)
        assertCGColorApprox(color, UIColor(red: 0.957, green: 0.635, blue: 0.380, alpha: 1.0).cgColor)
    }

    func testCgColor_injuryRiskJoint_returnsRed() {
        let analysis = ExpertAnalysis(phases: [
            ExpertAnalysis.Phase(
                phaseName: "Release",
                start: 0.0,
                end: 1.0,
                feedback: ExpertAnalysis.Phase.Feedback(
                    good: [],
                    slow: [],
                    injuryRisk: ["LEFT_KNEE"]
                )
            )
        ])
        let color = VideoCompositor.cgColor(for: "LEFT_KNEE", timestamp: 0.5, expertAnalysis: analysis)
        assertCGColorApprox(color, UIColor(red: 0.902, green: 0.224, blue: 0.275, alpha: 1.0).cgColor)
    }

    func testCgColor_outsidePhaseRange_returnsWhite() {
        let analysis = ExpertAnalysis(phases: [
            ExpertAnalysis.Phase(
                phaseName: "Delivery",
                start: 1.0,
                end: 2.0,
                feedback: ExpertAnalysis.Phase.Feedback(
                    good: ["LEFT_SHOULDER"],
                    slow: [],
                    injuryRisk: []
                )
            )
        ])
        let color = VideoCompositor.cgColor(for: "LEFT_SHOULDER", timestamp: 0.5, expertAnalysis: analysis)
        XCTAssertEqual(color, UIColor.white.cgColor)
    }

    // MARK: - Phase Lookup

    func testCurrentPhase_matchesCorrectPhase() {
        let phases = [
            AnalysisPhase(id: UUID(), name: "Run-Up", status: "GOOD", observation: "", tip: "", clipTimestamp: 0.0),
            AnalysisPhase(id: UUID(), name: "Loading", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 1.0),
            AnalysisPhase(id: UUID(), name: "Release", status: "GOOD", observation: "", tip: "", clipTimestamp: 2.0)
        ]

        let phase = VideoCompositor.currentPhase(at: 1.5, phases: phases)
        XCTAssertEqual(phase?.name, "Loading")
    }

    func testCurrentPhase_beforeFirstPhase_returnsNil() {
        let phases = [
            AnalysisPhase(id: UUID(), name: "Run-Up", status: "GOOD", observation: "", tip: "", clipTimestamp: 1.0)
        ]
        let phase = VideoCompositor.currentPhase(at: 0.5, phases: phases)
        XCTAssertNil(phase)
    }

    func testCurrentPhase_lastPhase_extendsToEnd() {
        let phases = [
            AnalysisPhase(id: UUID(), name: "Follow-Through", status: "GOOD", observation: "", tip: "", clipTimestamp: 2.0)
        ]
        let phase = VideoCompositor.currentPhase(at: 10.0, phases: phases)
        XCTAssertEqual(phase?.name, "Follow-Through")
    }

    // MARK: - Coordinate Mapping

    func testToScreenCoordinates_centerLandmark() {
        let landmark = PoseLandmark(name: "NOSE", index: 0, x: 0.5, y: 0.5, z: 0, visibility: 1.0)
        let size = CGSize(width: 1080, height: 1920)
        let point = SkeletonRenderer.toScreenCoordinates(landmark, size: size)
        XCTAssertEqual(point.x, 540, accuracy: 0.1)
        XCTAssertEqual(point.y, 960, accuracy: 0.1)
    }

    func testToScreenCoordinates_originLandmark() {
        let landmark = PoseLandmark(name: "NOSE", index: 0, x: 0, y: 0, z: 0, visibility: 1.0)
        let size = CGSize(width: 1080, height: 1920)
        let point = SkeletonRenderer.toScreenCoordinates(landmark, size: size)
        XCTAssertEqual(point.x, 0, accuracy: 0.1)
        XCTAssertEqual(point.y, 0, accuracy: 0.1)
    }

    func testToScreenCoordinates_bottomRight() {
        let landmark = PoseLandmark(name: "NOSE", index: 0, x: 1.0, y: 1.0, z: 0, visibility: 1.0)
        let size = CGSize(width: 1080, height: 1920)
        let point = SkeletonRenderer.toScreenCoordinates(landmark, size: size)
        XCTAssertEqual(point.x, 1080, accuracy: 0.1)
        XCTAssertEqual(point.y, 1920, accuracy: 0.1)
    }

    // MARK: - Helpers

    private func makeFrame(timestamp: Double, frameNumber: Int) -> FramePoseLandmarks {
        FramePoseLandmarks(
            frameNumber: frameNumber,
            timestamp: timestamp,
            landmarks: [
                PoseLandmark(name: "LEFT_SHOULDER", index: 11, x: 0.4, y: 0.3, z: 0, visibility: 0.9),
                PoseLandmark(name: "RIGHT_SHOULDER", index: 12, x: 0.6, y: 0.3, z: 0, visibility: 0.9)
            ]
        )
    }

    private func assertCGColorApprox(_ actual: CGColor, _ expected: CGColor, tolerance: CGFloat = 0.01, file: StaticString = #file, line: UInt = #line) {
        guard let a = actual.components, let e = expected.components else {
            XCTFail("Cannot get color components", file: file, line: line)
            return
        }
        let count = min(a.count, e.count)
        for i in 0..<count {
            XCTAssertEqual(a[i], e[i], accuracy: tolerance, "Component \(i) mismatch", file: file, line: line)
        }
    }
}
