import AVFoundation
import XCTest
@testable import wellBowled

@MainActor
final class SessionViewModelPromptTests: XCTestCase {

    func testCameraSwitchContextUsesFrontAndBackLabels() {
        let front = SessionViewModel.cameraSwitchContext(for: .front)
        let back = SessionViewModel.cameraSwitchContext(for: .back)

        XCTAssertTrue(front.contains("front camera"))
        XCTAssertTrue(back.contains("back camera"))
    }

    func testShouldEndSessionRecognizesExpectedCommands() {
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "end session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "please end the session now"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "can you end my session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "stop session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "please stop this session now"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "finish session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "finish this session"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "Could you wrap up the session?"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "session over"))
    }

    func testShouldEndSessionNormalizesNoise() {
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "END   the... session!!!"))
        XCTAssertTrue(SessionViewModel.shouldEndSession(from: "wrap-up the session"))
    }

    func testShouldEndSessionIgnoresUnrelatedSpeech() {
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "great ball keep going"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "switch camera"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "what is the plan"))
        XCTAssertFalse(SessionViewModel.shouldEndSession(from: "weekend session was good"))
    }
}
