import XCTest
@testable import wellBowled

final class SpeedCalcTests: XCTestCase {

    // MARK: - Speed KMH

    func test_typicalDelivery_120fps() {
        // 60 frames at 120fps = 0.5s transit = 20.12m / 0.5s = 40.24 m/s = 144.86 km/h
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 144.864, accuracy: 0.01)
    }

    func test_expressDelivery_120fps() {
        // 45 frames at 120fps = 0.375s = 20.12/0.375*3.6 = 193.15 km/h
        let speed = SpeedCalc.kmh(releaseFrame: 10, arrivalFrame: 55, fps: 120)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 193.152, accuracy: 0.01)
    }

    func test_slowDelivery_120fps() {
        // 100 frames at 120fps = 0.833s = 86.92 km/h
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 100, fps: 120)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 86.918, accuracy: 0.01)
    }

    func test_240fps_sameFrameDiff_differentSpeed() {
        // 60 frames at 240fps = 0.25s = 289.73 km/h (double the 120fps result)
        let speed120 = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 120)!
        let speed240 = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 240)!
        XCTAssertEqual(speed240, speed120 * 2, accuracy: 0.01)
    }

    func test_240fps_typicalDelivery() {
        // 120 frames at 240fps = 0.5s = 144.86 km/h (same as 60f@120fps)
        let speed = SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 120, fps: 240)
        XCTAssertEqual(speed!, 144.864, accuracy: 0.01)
    }

    func test_returnsNil_whenArrivalBeforeRelease() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 50, arrivalFrame: 30, fps: 120))
    }

    func test_returnsNil_whenFramesEqual() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 50, arrivalFrame: 50, fps: 120))
    }

    func test_returnsNil_whenZeroFPS() {
        XCTAssertNil(SpeedCalc.kmh(releaseFrame: 0, arrivalFrame: 60, fps: 0))
    }

    // MARK: - MPH conversion

    func test_mphConversion() {
        let mph = SpeedCalc.mph(kmh: 144.864)
        XCTAssertEqual(mph, 90.03, accuracy: 0.1)
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
