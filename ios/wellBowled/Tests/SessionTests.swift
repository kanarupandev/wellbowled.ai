import XCTest
@testable import wellBowled

final class SessionTests: XCTestCase {

    // MARK: - Lifecycle

    func testStartInitializesSession() {
        var session = Session()
        session.start()

        XCTAssertTrue(session.isActive)
        XCTAssertNotNil(session.startedAt)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.deliveryCount, 0)
        XCTAssertEqual(session.mode, .freePlay)
        XCTAssertNil(session.summary)
    }

    func testStartWithChallengeMode() {
        var session = Session()
        session.start(mode: .challenge)

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.mode, .challenge)
    }

    func testEndSetsInactiveAndEndTime() {
        var session = Session()
        session.start()
        session.end()

        XCTAssertFalse(session.isActive)
        XCTAssertNotNil(session.endedAt)
    }

    func testStartResetsAllState() {
        var session = Session()
        session.start()
        session.addDelivery(Delivery(timestamp: 1.0, sequence: 1))
        session.recordChallengeResult(hit: true)
        session.currentChallenge = "Yorker"

        // Start again — everything resets
        session.start()
        XCTAssertEqual(session.deliveryCount, 0)
        XCTAssertEqual(session.challengeHits, 0)
        XCTAssertEqual(session.challengeTotal, 0)
        XCTAssertNil(session.currentChallenge)
        XCTAssertNil(session.summary)
    }

    // MARK: - Deliveries

    func testAddDeliveryIncrementsCount() {
        var session = Session()
        session.start()

        session.addDelivery(Delivery(timestamp: 1.0, sequence: 1))
        XCTAssertEqual(session.deliveryCount, 1)

        session.addDelivery(Delivery(timestamp: 5.0, sequence: 2))
        XCTAssertEqual(session.deliveryCount, 2)
    }

    func testLastDeliveryReturnsLatest() {
        var session = Session()
        session.start()
        session.addDelivery(Delivery(timestamp: 1.0, sequence: 1))
        session.addDelivery(Delivery(timestamp: 5.0, sequence: 2))

        XCTAssertEqual(session.lastDelivery?.sequence, 2)
        XCTAssertEqual(session.lastDelivery?.timestamp, 5.0)
    }

    func testLastDeliveryNilWhenEmpty() {
        let session = Session()
        XCTAssertNil(session.lastDelivery)
    }

    // MARK: - Challenge Scoring

    func testChallengeScoreTracksHitsAndMisses() {
        var session = Session()
        session.start(mode: .challenge)

        session.recordChallengeResult(hit: true)
        session.recordChallengeResult(hit: false)
        session.recordChallengeResult(hit: true)

        XCTAssertEqual(session.challengeHits, 2)
        XCTAssertEqual(session.challengeTotal, 3)
    }

    func testChallengeScoreTextFormat() {
        var session = Session()
        session.start(mode: .challenge)

        session.recordChallengeResult(hit: true)
        session.recordChallengeResult(hit: true)
        session.recordChallengeResult(hit: false)

        XCTAssertEqual(session.challengeScoreText, "2/3 (66%)")
    }

    func testChallengeScoreTextEmptyWhenNoAttempts() {
        let session = Session()
        XCTAssertEqual(session.challengeScoreText, "")
    }

    // MARK: - Duration

    func testDurationZeroWhenNotStarted() {
        let session = Session()
        XCTAssertEqual(session.duration, 0)
    }

    func testDurationPositiveWhenActive() {
        var session = Session()
        session.start()
        // startedAt is Date(), so duration should be tiny but >= 0
        XCTAssertGreaterThanOrEqual(session.duration, 0)
    }

    // MARK: - Struct Value Semantics

    func testSessionIsValueType() {
        var session1 = Session()
        session1.start()
        session1.addDelivery(Delivery(timestamp: 1.0, sequence: 1))

        var session2 = session1 // copy
        session2.addDelivery(Delivery(timestamp: 2.0, sequence: 2))

        // Orignal should NOT be affected
        XCTAssertEqual(session1.deliveryCount, 1)
        XCTAssertEqual(session2.deliveryCount, 2)
    }
}
