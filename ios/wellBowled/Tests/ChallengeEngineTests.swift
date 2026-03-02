import XCTest
@testable import wellBowled

final class ChallengeEngineTests: XCTestCase {

    func testNextTargetRotatesInOrderWhenShuffleDisabled() {
        var engine = ChallengeEngine(targets: ["A", "B", "C"], shuffle: false)

        XCTAssertEqual(engine.nextTarget(), "A")
        XCTAssertEqual(engine.nextTarget(), "B")
        XCTAssertEqual(engine.nextTarget(), "C")
        XCTAssertEqual(engine.nextTarget(), "A")
    }

    func testResetReturnsCursorToStartWhenShuffleDisabled() {
        var engine = ChallengeEngine(targets: ["Yorker", "Bouncer"], shuffle: false)

        _ = engine.nextTarget()
        _ = engine.nextTarget()

        engine.reset(shuffle: false)
        XCTAssertEqual(engine.nextTarget(), "Yorker")
    }

    func testEmptyTargetPoolFallsBackToNonEmptyTarget() {
        var engine = ChallengeEngine(targets: [], shuffle: false)
        let target = engine.nextTarget()

        XCTAssertFalse(target.isEmpty)
    }

    func testFormatResultIncludesTargetStatusAndExplanation() {
        let result = ChallengeResult(
            matchesTarget: true,
            confidence: 0.91,
            explanation: "Hit yorker line and length",
            detectedLength: .yorker,
            detectedLine: .offStump
        )

        let text = ChallengeEngine.formatResult(target: "Yorker on off stump", result: result)
        XCTAssertTrue(text.contains("Yorker on off stump"))
        XCTAssertTrue(text.contains("HIT"))
        XCTAssertTrue(text.contains("Hit yorker line and length"))
    }
}
