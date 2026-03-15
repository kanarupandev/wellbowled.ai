import CoreGraphics
import XCTest
@testable import wellBowled

final class StumpCalibrationTests: XCTestCase {

    // MARK: - Factory

    private func makeCalibration(
        bowlerCenter: CGPoint = CGPoint(x: 0.5, y: 0.15),
        strikerCenter: CGPoint = CGPoint(x: 0.5, y: 0.85),
        frameWidth: Int = 1920,
        frameHeight: Int = 1080,
        fps: Int = 120,
        manual: Bool = false
    ) -> StumpCalibration {
        StumpCalibration(
            bowlerStumpCenter: bowlerCenter,
            strikerStumpCenter: strikerCenter,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            recordingFPS: fps,
            calibratedAt: Date(),
            isManualPlacement: manual
        )
    }

    // MARK: - Validity

    func testValidCalibration() {
        let cal = makeCalibration()
        XCTAssertTrue(cal.isValid)
    }

    func testInvalidWhenStumpsOverlap() {
        let cal = makeCalibration(
            bowlerCenter: CGPoint(x: 0.5, y: 0.5),
            strikerCenter: CGPoint(x: 0.5, y: 0.5)
        )
        XCTAssertFalse(cal.isValid)
    }

    func testInvalidWhenZeroFrameDimensions() {
        let cal = makeCalibration(frameWidth: 0, frameHeight: 0)
        XCTAssertFalse(cal.isValid)
    }

    func testInvalidWhenZeroFPS() {
        let cal = makeCalibration(fps: 0)
        XCTAssertFalse(cal.isValid)
    }

    // MARK: - Stump Separation

    func testStumpSeparationPixels() {
        // Stumps at y=0.15 and y=0.85 with same x → vertical separation = 0.70 * 1080 = 756px
        let cal = makeCalibration()
        XCTAssertEqual(cal.stumpSeparationPixels, 756.0, accuracy: 0.1)
    }

    func testPixelsPerMetre() {
        let cal = makeCalibration()
        let expected = 756.0 / 20.12 // ~37.57 px/m
        XCTAssertEqual(cal.pixelsPerMetre, expected, accuracy: 0.01)
    }

    // MARK: - Speed Computation

    func testSpeedKphForTypicalPace() {
        let cal = makeCalibration()
        // 130 kph → 36.11 m/s → transit = 20.12 / 36.11 ≈ 0.557s
        let transitTime = 20.12 / (130.0 / 3.6)
        let speed = cal.speedKph(transitTimeSeconds: transitTime)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 130.0, accuracy: 0.1)
    }

    func testSpeedKphForSlowBowler() {
        let cal = makeCalibration()
        // 80 kph → transit ≈ 0.906s
        let transitTime = 20.12 / (80.0 / 3.6)
        let speed = cal.speedKph(transitTimeSeconds: transitTime)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 80.0, accuracy: 0.1)
    }

    func testSpeedKphReturnsNilForTooFastTransit() {
        let cal = makeCalibration()
        // Transit of 0.1s → 724 kph → unrealistic
        XCTAssertNil(cal.speedKph(transitTimeSeconds: 0.1))
    }

    func testSpeedKphReturnsNilForTooSlowTransit() {
        let cal = makeCalibration()
        // Transit of 2.0s → 36 kph → below floor
        XCTAssertNil(cal.speedKph(transitTimeSeconds: 2.0))
    }

    func testSpeedKphAtBoundaries() {
        let cal = makeCalibration()
        // At exactly min transit (0.2s) → should still return a value
        XCTAssertNotNil(cal.speedKph(transitTimeSeconds: 0.2))
        // At exactly max transit (1.5s) → should still return a value
        XCTAssertNotNil(cal.speedKph(transitTimeSeconds: 1.5))
    }

    // MARK: - Speed Error Margin

    func testSpeedErrorAt120fps() {
        let cal = makeCalibration(fps: 120)
        // 130 kph transit ≈ 0.557s
        let transitTime = 20.12 / (130.0 / 3.6)
        let error = cal.speedErrorKph(transitTimeSeconds: transitTime, frameUncertainty: 2)
        XCTAssertNotNil(error)
        // At 120fps, ±2 frames = ±0.0167s → should give ±~4 kph error
        XCTAssertLessThan(error!, 6.0)
        XCTAssertGreaterThan(error!, 2.0)
    }

    func testSpeedErrorAt60fps() {
        let cal = makeCalibration(fps: 60)
        let transitTime = 20.12 / (130.0 / 3.6)
        let error = cal.speedErrorKph(transitTimeSeconds: transitTime, frameUncertainty: 2)
        XCTAssertNotNil(error)
        // At 60fps, ±2 frames = ±0.0333s → larger error than 120fps
        XCTAssertGreaterThan(error!, 4.0)
    }

    // MARK: - ROI Rects

    func testBowlerROIIsAroundBowlerCenter() {
        let cal = makeCalibration(bowlerCenter: CGPoint(x: 0.5, y: 0.15))
        let roi = cal.bowlerROI
        XCTAssertTrue(roi.contains(CGPoint(x: 0.5, y: 0.15)))
        XCTAssertEqual(roi.width, Double(WBConfig.speedROIWidthRatio), accuracy: 0.001)
    }

    func testStrikerROIIsAroundStrikerCenter() {
        let cal = makeCalibration(strikerCenter: CGPoint(x: 0.5, y: 0.85))
        let roi = cal.strikerROI
        XCTAssertTrue(roi.contains(CGPoint(x: 0.5, y: 0.85)))
    }

    func testROIClampedToZero() {
        // Stump near edge — ROI should not go negative
        let cal = makeCalibration(bowlerCenter: CGPoint(x: 0.02, y: 0.02))
        let roi = cal.bowlerROI
        XCTAssertGreaterThanOrEqual(roi.origin.x, 0)
        XCTAssertGreaterThanOrEqual(roi.origin.y, 0)
    }

    // MARK: - Codable Round Trip

    func testCodableRoundTrip() throws {
        let original = makeCalibration()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StumpCalibration.self, from: data)

        XCTAssertEqual(decoded.bowlerStumpCenter, original.bowlerStumpCenter)
        XCTAssertEqual(decoded.strikerStumpCenter, original.strikerStumpCenter)
        XCTAssertEqual(decoded.frameWidth, original.frameWidth)
        XCTAssertEqual(decoded.frameHeight, original.frameHeight)
        XCTAssertEqual(decoded.recordingFPS, original.recordingFPS)
        XCTAssertEqual(decoded.isManualPlacement, original.isManualPlacement)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - SpeedEstimate Codable

    func testSpeedEstimateCodableRoundTrip() throws {
        let estimate = SpeedEstimate(
            kph: 127.3,
            confidence: 0.85,
            method: .frameDifferencing,
            transitTimeSeconds: 0.569,
            errorMarginKph: 3.8,
            bowlerFrameIndex: 42,
            strikerFrameIndex: 110
        )

        let data = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(SpeedEstimate.self, from: data)

        XCTAssertEqual(decoded.kph, 127.3, accuracy: 0.01)
        XCTAssertEqual(decoded.confidence, 0.85, accuracy: 0.01)
        XCTAssertEqual(decoded.method, .frameDifferencing)
        XCTAssertEqual(decoded.transitTimeSeconds, 0.569, accuracy: 0.001)
        XCTAssertEqual(decoded.errorMarginKph!, 3.8, accuracy: 0.01)
        XCTAssertEqual(decoded.bowlerFrameIndex, 42)
        XCTAssertEqual(decoded.strikerFrameIndex, 110)
    }

    // MARK: - Pitch Length Constant

    func testPitchLengthIsLawOfCricketStandard() {
        XCTAssertEqual(StumpCalibration.pitchLengthMetres, 20.12, accuracy: 0.001)
    }
}
