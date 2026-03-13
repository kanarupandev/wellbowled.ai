import XCTest
import AVFoundation
@testable import wellBowled

final class CoreDeterminismTests: XCTestCase {

    func testSessionResultsPlannerIsDeterministicAcrossConcurrentCalls() async {
        let phases = [
            AnalysisPhase(name: "Run-up", status: "GOOD", observation: "", tip: "", clipTimestamp: 0.7),
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.2),
            AnalysisPhase(name: "Follow-through", status: "GOOD", observation: "", tip: "", clipTimestamp: 3.9)
        ]
        let expert = ExpertAnalysis(
            phases: [
                ExpertAnalysis.Phase(
                    phaseName: "Release",
                    start: 2.0,
                    end: 2.6,
                    feedback: ExpertAnalysis.Phase.Feedback(
                        good: [],
                        slow: ["RIGHT_ELBOW"],
                        injuryRisk: ["RIGHT_WRIST"]
                    )
                )
            ]
        )

        let baseline = SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: expert, limit: 3)

        var collected: [[SessionPhaseSuggestion]] = []
        await withTaskGroup(of: [SessionPhaseSuggestion].self) { group in
            for _ in 0..<64 {
                group.addTask {
                    SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: expert, limit: 3)
                }
            }
            for await value in group {
                collected.append(value)
            }
        }

        XCTAssertEqual(collected.count, 64)
        XCTAssertTrue(collected.allSatisfy { $0 == baseline })
    }

    func testLandmarksMappingIsDeterministicAcrossConcurrentCalls() async {
        let data = LandmarksData(
            fps: 30,
            w: 640,
            h: 480,
            connections: [],
            frames: [
                FrameLandmarks(
                    t: 0.9,
                    p: "run_up",
                    l: [BackendLandmark(i: 16, n: "RIGHT_WRIST", x: 0.3, y: 0.4, v: 0.9, f: "good")]
                ),
                FrameLandmarks(
                    t: 1.8,
                    p: "release",
                    l: [BackendLandmark(i: 14, n: "RIGHT_ELBOW", x: 0.35, y: 0.45, v: 0.9, f: "injury_risk")]
                )
            ]
        )

        let baseline = signature(of: data.toExpertAnalysisFromGeminiFeedback())
        var signatures: [String] = []

        await withTaskGroup(of: String.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    self.signature(of: data.toExpertAnalysisFromGeminiFeedback())
                }
            }
            for await sig in group {
                signatures.append(sig)
            }
        }

        XCTAssertEqual(signatures.count, 64)
        XCTAssertTrue(signatures.allSatisfy { $0 == baseline })
    }

    private func signature(of analysis: ExpertAnalysis?) -> String {
        guard let analysis else { return "nil" }
        return analysis.phases.map { phase in
            "\(phase.phaseName)|\(phase.start)|\(phase.end)|\(phase.feedback.good.joined(separator: ","))|\(phase.feedback.slow.joined(separator: ","))|\(phase.feedback.injuryRisk.joined(separator: ","))"
        }.joined(separator: "||")
    }
}

@MainActor
final class PreviewLayerHostViewTests: XCTestCase {

    func testSetPreviewLayerAttachesProvidedLayer() {
        let host = PreviewLayerHostView(frame: CGRect(x: 0, y: 0, width: 120, height: 240))
        let layer = AVCaptureVideoPreviewLayer()

        host.setPreviewLayer(layer)

        XCTAssertTrue(layer.superlayer === host.layer)
        XCTAssertTrue(host.layer.sublayers?.contains(where: { $0 === layer }) ?? false)
    }

    func testSetPreviewLayerReplacesPreviousLayer() {
        let host = PreviewLayerHostView(frame: CGRect(x: 0, y: 0, width: 120, height: 240))
        let firstLayer = AVCaptureVideoPreviewLayer()
        let secondLayer = AVCaptureVideoPreviewLayer()

        host.setPreviewLayer(firstLayer)
        host.setPreviewLayer(secondLayer)

        XCTAssertNil(firstLayer.superlayer)
        XCTAssertTrue(secondLayer.superlayer === host.layer)
        XCTAssertFalse(host.layer.sublayers?.contains(where: { $0 === firstLayer }) ?? false)
    }

    func testLayoutUpdatesAttachedLayerFrame() {
        let host = PreviewLayerHostView(frame: CGRect(x: 0, y: 0, width: 120, height: 240))
        let layer = AVCaptureVideoPreviewLayer()

        host.setPreviewLayer(layer)
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 320)
        host.layoutIfNeeded()

        XCTAssertEqual(layer.frame, host.bounds)
    }
}
