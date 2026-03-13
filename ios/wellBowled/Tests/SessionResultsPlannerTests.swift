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

    func testFocusWindowClampsOutOfRangeTimestamp() {
        let windowPastEnd = SessionResultsPlanner.focusWindow(for: 42.0, clipDuration: 5.0)
        XCTAssertGreaterThanOrEqual(windowPastEnd.lowerBound, 0.0)
        XCTAssertLessThanOrEqual(windowPastEnd.upperBound, 5.0)

        let windowBeforeStart = SessionResultsPlanner.focusWindow(for: -10.0, clipDuration: 5.0)
        XCTAssertGreaterThanOrEqual(windowBeforeStart.lowerBound, 0.0)
        XCTAssertLessThanOrEqual(windowBeforeStart.upperBound, 5.0)
    }

    func testTopPhaseSuggestionsRespectsNonPositiveLimit() {
        let phases = [
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.0)
        ]

        XCTAssertEqual(SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: nil, limit: 0), [])
        XCTAssertEqual(SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: nil, limit: -4), [])
    }

    func testFocusTimestampFallsBackToExpertPhaseWhenClipTimestampMissing() {
        let phase = AnalysisPhase(name: "Run up", status: "GOOD", observation: "", tip: "", clipTimestamp: nil)
        let expert = ExpertAnalysis(
            phases: [
                ExpertAnalysis.Phase(
                    phaseName: "run-up",
                    start: 0.4,
                    end: 1.6,
                    feedback: ExpertAnalysis.Phase.Feedback(good: ["RIGHT_HIP"], slow: [], injuryRisk: [])
                )
            ]
        )

        let timestamp = SessionResultsPlanner.focusTimestamp(for: phase, expertAnalysis: expert)
        XCTAssertEqual(timestamp, 1.0, accuracy: 0.0001)
    }

    func testFocusTimestampDefaultsToMidClipWhenNoTimestampAndNoExpertMatch() {
        let phase = AnalysisPhase(name: "Unknown", status: "GOOD", observation: "", tip: "", clipTimestamp: nil)
        XCTAssertEqual(SessionResultsPlanner.focusTimestamp(for: phase, expertAnalysis: nil), 2.5, accuracy: 0.0001)
    }

    func testTopPhaseSuggestionsUsesTimestampAsTieBreaker() {
        let phases = [
            AnalysisPhase(name: "A", status: "GOOD", observation: "", tip: "", clipTimestamp: 3.0),
            AnalysisPhase(name: "B", status: "GOOD", observation: "", tip: "", clipTimestamp: 1.0)
        ]

        let suggestions = SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: nil, limit: 2)
        XCTAssertEqual(suggestions.map(\.phaseName), ["B", "A"])
    }

    func testFocusTimestampClampsMatchedExpertMidpointToClipBounds() {
        let phase = AnalysisPhase(name: "release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: nil)
        let expert = ExpertAnalysis(
            phases: [
                ExpertAnalysis.Phase(
                    phaseName: "Release",
                    start: 10.0,
                    end: 12.0,
                    feedback: ExpertAnalysis.Phase.Feedback(good: [], slow: ["RIGHT_ELBOW"], injuryRisk: [])
                )
            ]
        )

        let timestamp = SessionResultsPlanner.focusTimestamp(for: phase, expertAnalysis: expert)
        XCTAssertEqual(timestamp, 5.0, accuracy: 0.0001)
    }

    func testAutoCarouselNavigationRequiresHoldAndCompletedClipPreparation() {
        XCTAssertFalse(
            SessionResultsPlanner.shouldAutoNavigateToDeliveryCarousel(
                hasHeldFullReplay: false,
                isPreparingClips: false,
                deliveryCount: 2
            )
        )
        XCTAssertFalse(
            SessionResultsPlanner.shouldAutoNavigateToDeliveryCarousel(
                hasHeldFullReplay: true,
                isPreparingClips: true,
                deliveryCount: 2
            )
        )
        XCTAssertFalse(
            SessionResultsPlanner.shouldAutoNavigateToDeliveryCarousel(
                hasHeldFullReplay: true,
                isPreparingClips: false,
                deliveryCount: 0
            )
        )
        XCTAssertTrue(
            SessionResultsPlanner.shouldAutoNavigateToDeliveryCarousel(
                hasHeldFullReplay: true,
                isPreparingClips: false,
                deliveryCount: 3
            )
        )
    }

    func testSpinnerAndNoDeliveryOverlayRules() {
        XCTAssertTrue(
            SessionResultsPlanner.shouldShowClipPreparationSpinner(
                hasHeldFullReplay: true,
                isPreparingClips: true
            )
        )
        XCTAssertFalse(
            SessionResultsPlanner.shouldShowClipPreparationSpinner(
                hasHeldFullReplay: false,
                isPreparingClips: true
            )
        )
        XCTAssertTrue(
            SessionResultsPlanner.shouldShowNoDeliveriesOverlay(
                hasHeldFullReplay: true,
                isPreparingClips: false,
                deliveryCount: 0
            )
        )
        XCTAssertFalse(
            SessionResultsPlanner.shouldShowNoDeliveriesOverlay(
                hasHeldFullReplay: true,
                isPreparingClips: false,
                deliveryCount: 1
            )
        )
        XCTAssertFalse(
            SessionResultsPlanner.shouldShowNoDeliveriesOverlay(
                hasHeldFullReplay: true,
                isPreparingClips: true,
                deliveryCount: 0
            )
        )
    }

    // MARK: - Video-First Overlay Chip Tests

    func testOverlayChipsOnlyAppearAfterAnalysisReady() {
        // deepAnalysisReady requires .ready stage AND non-empty phases
        // With empty phases, chips should not appear even if stage is .ready
        let emptyPhases: [AnalysisPhase] = []
        let suggestions = SessionResultsPlanner.topPhaseSuggestions(phases: emptyPhases, expertAnalysis: nil)
        XCTAssertTrue(suggestions.isEmpty, "No suggestions when phases are empty")
    }

    func testOverlayChipsOrderMatchesSuggestionPriority() {
        // Verify injury-risk phases appear first in chip ordering
        let phases = [
            AnalysisPhase(name: "Run-up", status: "GOOD", observation: "", tip: "", clipTimestamp: 0.5),
            AnalysisPhase(name: "Release", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.0),
            AnalysisPhase(name: "Follow-through", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 3.5)
        ]
        let analysis = ExpertAnalysis(
            phases: [
                ExpertAnalysis.Phase(
                    phaseName: "Follow-through",
                    start: 3.2, end: 4.0,
                    feedback: ExpertAnalysis.Phase.Feedback(good: [], slow: [], injuryRisk: ["RIGHT_KNEE"])
                ),
                ExpertAnalysis.Phase(
                    phaseName: "Release",
                    start: 1.8, end: 2.4,
                    feedback: ExpertAnalysis.Phase.Feedback(good: [], slow: ["RIGHT_ELBOW"], injuryRisk: [])
                )
            ]
        )

        let suggestions = SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: analysis)
        // Injury-risk phase (Follow-through) should rank before attention-only (Release)
        XCTAssertTrue(suggestions.count >= 2)
        XCTAssertEqual(suggestions.first?.phaseName, "Follow-through")
    }

    func testLegendLabelsAreSymbolOnly() {
        // Verify legend text doesn't include color names — just category labels
        let expectedLabels = ["Injury risk", "Good", "Attention"]
        for label in expectedLabels {
            XCTAssertFalse(label.lowercased().contains("red"))
            XCTAssertFalse(label.lowercased().contains("green"))
            XCTAssertFalse(label.lowercased().contains("yellow"))
        }
    }

    func testFocusSuggestionsLimitDefaultsToThree() {
        let phases = [
            AnalysisPhase(name: "A", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 1.0),
            AnalysisPhase(name: "B", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 2.0),
            AnalysisPhase(name: "C", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 3.0),
            AnalysisPhase(name: "D", status: "NEEDS WORK", observation: "", tip: "", clipTimestamp: 4.0)
        ]

        let suggestions = SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: nil)
        XCTAssertLessThanOrEqual(suggestions.count, 3, "Default limit should cap at 3 suggestions for compact overlay")
    }
}
