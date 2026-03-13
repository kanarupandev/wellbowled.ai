import XCTest
@testable import wellBowled

final class ExpertAnalysisBuilderTests: XCTestCase {

    func testBuildReturnsNilWhenNoClipTimestampsPresent() {
        let phases = [
            AnalysisPhase(name: "Run-up", status: "GOOD", observation: "", tip: "", clipTimestamp: nil),
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: nil)
        ]

        XCTAssertNil(ExpertAnalysisBuilder.build(from: phases))
    }

    func testBuildSortsByTimestampAndCreatesSequentialRanges() {
        let phases = [
            AnalysisPhase(name: "Follow-through", status: "GOOD", observation: "", tip: "", clipTimestamp: 3.6),
            AnalysisPhase(name: "Run-up", status: "GOOD", observation: "", tip: "", clipTimestamp: 0.4),
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.0)
        ]

        let built = ExpertAnalysisBuilder.build(from: phases)
        XCTAssertNotNil(built)

        guard let built else { return }
        XCTAssertEqual(built.phases.map(\.phaseName), ["Run-up", "Release", "Follow-through"])
        XCTAssertEqual(built.phases[0].start, 0.4, accuracy: 0.0001)
        XCTAssertEqual(built.phases[0].end, 2.0, accuracy: 0.0001)
        XCTAssertEqual(built.phases[1].start, 2.0, accuracy: 0.0001)
        XCTAssertEqual(built.phases[1].end, 3.6, accuracy: 0.0001)
        XCTAssertEqual(built.phases[2].start, 3.6, accuracy: 0.0001)
        XCTAssertEqual(built.phases[2].end, 5.1, accuracy: 0.0001)
    }

    func testBuildMapsFeedbackBucketsForGoodAndNeedsWork() {
        let phases = [
            AnalysisPhase(name: "Run-up", status: "GOOD", observation: "", tip: "", clipTimestamp: 0.5),
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.0)
        ]

        let built = ExpertAnalysisBuilder.build(from: phases)
        XCTAssertNotNil(built)
        guard let built else { return }

        let runup = built.phases[0]
        XCTAssertEqual(Set(runup.feedback.good), ExpertAnalysisMapper.keyJoints)
        XCTAssertTrue(runup.feedback.slow.isEmpty)
        XCTAssertTrue(runup.feedback.injuryRisk.isEmpty)

        let release = built.phases[1]
        XCTAssertEqual(release.feedback.slow, ExpertAnalysisBuilder.bowlingArm)
        XCTAssertTrue(release.feedback.good.isEmpty)
        XCTAssertTrue(release.feedback.injuryRisk.isEmpty)
    }
}
