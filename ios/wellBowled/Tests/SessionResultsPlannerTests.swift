import XCTest
@testable import wellBowled

final class SessionResultsPlannerTests: XCTestCase {

    func testTelemetryMessageFallsBackAfterFortySeconds() {
        XCTAssertEqual(
            SessionResultsPlanner.telemetryMessage(elapsedSeconds: 0),
            SessionResultsPlanner.telemetryMessages[0]
        )
        XCTAssertNotEqual(SessionResultsPlanner.telemetryMessage(elapsedSeconds: 38), "Analyzing...")
        XCTAssertEqual(SessionResultsPlanner.telemetryMessage(elapsedSeconds: 40), "Analyzing...")
        XCTAssertEqual(SessionResultsPlanner.telemetryMessage(elapsedSeconds: 58), "Analyzing...")
    }

    func testTopPhaseSuggestionsPrioritizeInjuryRisk() {
        let phases = [
            AnalysisPhase(name: "Run-up", status: "GOOD", observation: "", tip: "", clipTimestamp: 0.8),
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.0),
            AnalysisPhase(name: "Follow-through", status: "GOOD", observation: "", tip: "", clipTimestamp: 3.4),
            AnalysisPhase(name: "Landing", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 4.2)
        ]

        let analysis = ExpertAnalysis(
            phases: [
                ExpertAnalysis.Phase(
                    phaseName: "Release",
                    start: 1.8,
                    end: 2.4,
                    feedback: ExpertAnalysis.Phase.Feedback(
                        good: [],
                        slow: ["RIGHT_ELBOW"],
                        injuryRisk: ["RIGHT_WRIST", "RIGHT_SHOULDER"]
                    )
                ),
                ExpertAnalysis.Phase(
                    phaseName: "Landing",
                    start: 3.8,
                    end: 4.5,
                    feedback: ExpertAnalysis.Phase.Feedback(
                        good: [],
                        slow: ["LEFT_KNEE"],
                        injuryRisk: []
                    )
                )
            ]
        )

        let suggestions = SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: analysis)
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions.first?.phaseName, "Release")
    }

    func testFocusWindowClampsWithinClipDuration() {
        let windowNearStart = SessionResultsPlanner.focusWindow(for: 0.2, clipDuration: 5.0)
        XCTAssertEqual(windowNearStart.lowerBound, 0.0, accuracy: 0.0001)
        XCTAssertLessThan(windowNearStart.upperBound, 5.0)

        let windowNearEnd = SessionResultsPlanner.focusWindow(for: 4.9, clipDuration: 5.0)
        XCTAssertEqual(windowNearEnd.upperBound, 5.0, accuracy: 0.0001)
        XCTAssertLessThan(windowNearEnd.lowerBound, 5.0)
    }
}
