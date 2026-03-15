import XCTest
@testable import wellBowled

final class EnumsTests: XCTestCase {

    // MARK: - PaceBand

    func testPaceBandFromAngularVelocity() {
        XCTAssertEqual(PaceBand.from(angularVelocity: 2000), .quick)
        XCTAssertEqual(PaceBand.from(angularVelocity: 1501), .quick)
        XCTAssertEqual(PaceBand.from(angularVelocity: 1200), .medium)
        XCTAssertEqual(PaceBand.from(angularVelocity: 801), .medium)
        XCTAssertEqual(PaceBand.from(angularVelocity: 500), .slow)
        XCTAssertEqual(PaceBand.from(angularVelocity: 0), .slow)
    }

    func testPaceBandFromNegativeVelocity() {
        // Left-arm bowlers produce negative omega
        XCTAssertEqual(PaceBand.from(angularVelocity: -1600), .quick)
        XCTAssertEqual(PaceBand.from(angularVelocity: -1000), .medium)
        XCTAssertEqual(PaceBand.from(angularVelocity: -400), .slow)
    }

    func testPaceBandLabels() {
        XCTAssertEqual(PaceBand.quick.label, "Quick")
        XCTAssertEqual(PaceBand.medium.label, "Medium pace")
        XCTAssertEqual(PaceBand.slow.label, "Slow")
    }

    func testPaceBandBoundaryValues() {
        // Exactly at threshold boundaries
        XCTAssertEqual(PaceBand.from(angularVelocity: 1500), .medium) // not > 1500
        XCTAssertEqual(PaceBand.from(angularVelocity: 800), .slow)    // not > 800
    }

    // MARK: - Delivery Enums

    func testDeliveryStatusRawValues() {
        XCTAssertEqual(DeliveryStatus.detecting.rawValue, "LOCAL VISION SCAN")
        XCTAssertEqual(DeliveryStatus.success.rawValue, "QUALIFIED")
        XCTAssertEqual(DeliveryStatus.failed.rawValue, "REJECTED")
    }

    func testDeliveryLengthCodable() throws {
        let length = DeliveryLength.goodLength
        let data = try JSONEncoder().encode(length)
        let decoded = try JSONDecoder().decode(DeliveryLength.self, from: data)
        XCTAssertEqual(decoded, .goodLength)
        XCTAssertEqual(decoded.rawValue, "good_length")
    }

    func testDeliveryLineCodable() throws {
        let line = DeliveryLine.offStump
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(DeliveryLine.self, from: data)
        XCTAssertEqual(decoded, .offStump)
    }

    // MARK: - Session Mode

    func testSessionModeFinePrintLabel() {
        XCTAssertEqual(SessionMode.freePlay.finePrintLabel, "Mode: Free")
        XCTAssertEqual(SessionMode.challenge.finePrintLabel, "Mode: Challenge")
    }

    func testSessionModeFromToolArgument() {
        XCTAssertEqual(SessionMode.fromToolArgument("free"), .freePlay)
        XCTAssertEqual(SessionMode.fromToolArgument("freePlay"), .freePlay)
        XCTAssertEqual(SessionMode.fromToolArgument("challenge"), .challenge)
        XCTAssertNil(SessionMode.fromToolArgument("invalid"))
    }

    // MARK: - Delivery Model

    func testDeliveryDefaultValues() {
        let delivery = Delivery(timestamp: 10.5, sequence: 3)

        XCTAssertEqual(delivery.timestamp, 10.5)
        XCTAssertEqual(delivery.sequence, 3)
        XCTAssertEqual(delivery.status, .detecting)
        XCTAssertNil(delivery.report)
        XCTAssertNil(delivery.speed)
        XCTAssertTrue(delivery.tips.isEmpty)
        XCTAssertFalse(delivery.isFavorite)
    }

    func testDeliveryCodableRoundTrip() throws {
        let delivery = Delivery(
            timestamp: 15.3,
            report: "Nice length ball",
            speed: "120 kph",
            tips: ["Keep wrist behind the ball"],
            status: .success,
            sequence: 5,
            isFavorite: true
        )

        let data = try JSONEncoder().encode(delivery)
        let decoded = try JSONDecoder().decode(Delivery.self, from: data)

        XCTAssertEqual(decoded.timestamp, delivery.timestamp)
        XCTAssertEqual(decoded.report, delivery.report)
        XCTAssertEqual(decoded.speed, delivery.speed)
        XCTAssertEqual(decoded.tips, delivery.tips)
        XCTAssertEqual(decoded.status, delivery.status)
        XCTAssertEqual(decoded.sequence, delivery.sequence)
        XCTAssertEqual(decoded.isFavorite, delivery.isFavorite)
    }

    // MARK: - Speed Estimation Method

    func testSpeedEstimationMethodCodable() throws {
        let method = SpeedEstimationMethod.frameDifferencing
        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(SpeedEstimationMethod.self, from: data)
        XCTAssertEqual(decoded, .frameDifferencing)
        XCTAssertEqual(decoded.rawValue, "frame_differencing")
    }

    func testSpeedEstimationMethodGeminiEstimate() throws {
        let method = SpeedEstimationMethod.geminiEstimate
        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(SpeedEstimationMethod.self, from: data)
        XCTAssertEqual(decoded, .geminiEstimate)
    }

    // MARK: - DeliveryAnalysis

    func testDeliveryAnalysisCodable() throws {
        let analysis = DeliveryAnalysis(
            paceEstimate: "95-100 kph",
            length: .goodLength,
            line: .offStump,
            type: .seam,
            observation: "Good seam position",
            confidence: 0.85
        )

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(DeliveryAnalysis.self, from: data)

        XCTAssertEqual(decoded.paceEstimate, "95-100 kph")
        XCTAssertEqual(decoded.length, .goodLength)
        XCTAssertEqual(decoded.line, .offStump)
        XCTAssertEqual(decoded.type, .seam)
        XCTAssertEqual(decoded.confidence, 0.85, accuracy: 0.001)
    }
}
