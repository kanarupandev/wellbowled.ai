import AVFoundation
import XCTest
@testable import wellBowled

@MainActor
final class SessionViewModelPromptTests: XCTestCase {

    func testProactiveGreetingPromptForFreePlayAsksToGreetAndInvite() {
        let prompt = SessionViewModel.proactiveGreetingPrompt(mode: .freePlay, challengeTarget: nil)

        XCTAssertTrue(prompt.contains("proactive greeting"))
        XCTAssertTrue(prompt.contains("What's the plan for today?"))
        XCTAssertTrue(prompt.contains("Wait about 5 seconds"))
        XCTAssertTrue(prompt.contains("pilot run"))
        XCTAssertTrue(prompt.contains("Session started"))
        XCTAssertTrue(prompt.contains("switch_session_mode"))
    }

    func testProactiveGreetingPromptForChallengeIncludesModeSwitchGuidance() {
        let prompt = SessionViewModel.proactiveGreetingPrompt(mode: .challenge, challengeTarget: nil)

        XCTAssertTrue(prompt.contains("What's the plan for today?"))
        XCTAssertTrue(prompt.contains("Wait about 5 seconds"))
        XCTAssertTrue(prompt.contains("challenge mode"))
        XCTAssertTrue(prompt.contains("switch to free mode"))
        XCTAssertTrue(prompt.contains("switch_session_mode"))
        XCTAssertTrue(prompt.contains("pilot run"))
        XCTAssertTrue(prompt.contains("Session started"))
        XCTAssertTrue(prompt.contains("No target yet"))
    }

    func testProactiveGreetingPromptForChallengeIncludesTargetWhenPresent() {
        let target = "Yorker on off stump"
        let prompt = SessionViewModel.proactiveGreetingPrompt(mode: .challenge, challengeTarget: target)

        XCTAssertTrue(prompt.contains(target))
    }

    func testCameraSwitchContextUsesFrontAndBackLabels() {
        let front = SessionViewModel.cameraSwitchContext(for: .front)
        let back = SessionViewModel.cameraSwitchContext(for: .back)

        XCTAssertTrue(front.contains("front camera"))
        XCTAssertTrue(back.contains("back camera"))
    }

    func testPlanningRepromptPromptIsShortAndNatural() {
        let prompt = SessionViewModel.planningRepromptPrompt(mode: .freePlay)
        XCTAssertTrue(prompt.contains("No clear plan response yet"))
        XCTAssertTrue(prompt.contains("What's the plan for today?"))
    }

    func testPostPilotPromptForChallengeIncludesTarget() {
        let prompt = SessionViewModel.postPilotPrompt(mode: .challenge, target: "Yorker on off stump")
        XCTAssertTrue(prompt.contains("Session started"))
        XCTAssertTrue(prompt.contains("Yorker on off stump"))
    }

    func testShouldEndSessionRecognizesExpectedCommands() {
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "end session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "please end the session now"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "stop session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "finish session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "session over"))
    }

    func testShouldEndSessionIgnoresUnrelatedSpeech() {
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "great ball keep going"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "switch camera"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "what is the plan"))
    }
}
