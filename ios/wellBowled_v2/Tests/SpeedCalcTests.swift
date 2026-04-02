import XCTest
@testable import wellBowled

final class SpeedCalcTests: XCTestCase {

    private let dist = SpeedCalc.defaultDistanceMeters  // 17.68m

    // MARK: - Speed KMH

    func test_typicalDelivery_120fps() {
        // 60 frames at 120fps = 0.5s transit = 17.68m / 0.5s * 3.6 = 127.30 km/h
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120, distanceMeters: dist)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 127.296, accuracy: 0.01)
    }

    func test_expressDelivery_120fps() {
        // 45 frames at 120fps = 0.375s = 17.68/0.375*3.6 = 169.73 km/h
        let speed = SpeedCalc.kmh(releaseFrame: 10, arrivalFrame: 55, fps: 120, distanceMeters: dist)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 169.728, accuracy: 0.01)
    }

    func test_slowDelivery_120fps() {
        // 100 frames at 120fps = 0.833s = 76.38 km/h
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 100, fps: 120, distanceMeters: dist)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 76.378, accuracy: 0.01)
    }

    func test_240fps_sameFrameDiff_differentSpeed() {
        // 60 frames at 240fps = 0.25s vs 120fps = 0.5s -> double the speed
        let speed120 = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120, distanceMeters: dist)!
        let speed240 = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 240, distanceMeters: dist)!
        XCTAssertEqual(speed240, speed120 * 2, accuracy: 0.01)
    }

    func test_240fps_typicalDelivery() {
        // 120 frames at 240fps = 0.5s = same as 60f@120fps
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 120, fps: 240, distanceMeters: dist)
        XCTAssertEqual(speed!, 127.296, accuracy: 0.01)
    }

    func test_customDistance() {
        // Full pitch stump-to-stump = 20.12m
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120, distanceMeters: 20.12)
        XCTAssertEqual(speed!, 144.864, accuracy: 0.01)
    }

    func test_returnsNil_whenArrivalBeforeRelease() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 50, arrivalFrame: 30, fps: 120, distanceMeters: dist))
    }

    func test_returnsNil_whenFramesEqual() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 50, arrivalFrame: 50, fps: 120, distanceMeters: dist))
    }

    func test_returnsNil_whenZeroFPS() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 0, distanceMeters: dist))
    }

    func test_returnsNil_whenZeroDistance() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120, distanceMeters: 0))
    }

    func test_returnsNil_whenNegativeDistance() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120, distanceMeters: -5))
    }

    // MARK: - MPH conversion

    func test_mphConversion() {
        let mph = SpeedCalc.mph(kmh: 127.296)
        XCTAssertEqual(mph, 79.11, accuracy: 0.1)
    }

    // MARK: - Clamping

    func test_clamp_negativeBecomesZero() {
        XCTAssertEqual(SpeedCalc.clampedIndex(-5, total: 100), 0)
    }

    func test_clamp_beyondTotalClampsToMax() {
        XCTAssertEqual(SpeedCalc.clampedIndex(9999, total: 100), 99)
    }

    func test_clamp_validIndexUnchanged() {
        XCTAssertEqual(SpeedCalc.clampedIndex(50, total: 100), 50)
    }

    func test_clamp_zeroIsValid() {
        XCTAssertEqual(SpeedCalc.clampedIndex(0, total: 100), 0)
    }

    func test_clamp_lastFrameIsValid() {
        XCTAssertEqual(SpeedCalc.clampedIndex(99, total: 100), 99)
    }

    // MARK: - Time calculation

    func test_timeSeconds_atZero() {
        XCTAssertEqual(SpeedCalc.timeSeconds(frame: 0, fps: 120), 0.0)
    }

    func test_timeSeconds_atOneSecond() {
        XCTAssertEqual(SpeedCalc.timeSeconds(frame: 120, fps: 120), 1.0)
    }

    func test_timeSeconds_240fps() {
        XCTAssertEqual(SpeedCalc.timeSeconds(frame: 240, fps: 240), 1.0)
    }
}
