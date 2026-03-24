import XCTest
@testable import wellBowled

final class CliffDetectorTests: XCTestCase {

    private func makeDetector(
        fps: Double = 240,
        minDisarmSeconds: Double = 0.05,
        rearmQuietSeconds: Double = 0.05,
        quietThreshold: Double = 0.8
    ) -> CliffDetector {
        CliffDetector(
            fps: fps,
            minDisarmSeconds: minDisarmSeconds,
            rearmQuietSeconds: rearmQuietSeconds,
            quietThreshold: quietThreshold
        )
    }

    // MARK: - Detection

    func testDetectsCliff() {
        let d = makeDetector()
        let energies: [Double] = [0, 0, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0, 1.0]
        var result: CliffDetection?
        for (i, e) in energies.enumerated() {
            if let r = d.feedEnergy(e, atFrame: i) { result = r }
        }
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.meetFrame, 7)
        XCTAssertEqual(d.state, .stumpsHit)
    }

    func testNoDetectionWhenDropInsufficient() {
        let d = makeDetector()
        let energies: [Double] = [0, 0, 1.0, 2.0, 4.0, 8.0, 10.0, 6.0, 5.0]
        for (i, e) in energies.enumerated() {
            XCTAssertNil(d.feedEnergy(e, atFrame: i))
        }
        XCTAssertEqual(d.state, .monitoring)
    }

    func testNoDetectionWhenEnergyTooLow() {
        let d = makeDetector()
        let energies: [Double] = [0, 0, 0.5, 1.0, 1.5, 0.1]
        for (i, e) in energies.enumerated() {
            XCTAssertNil(d.feedEnergy(e, atFrame: i))
        }
    }

    // MARK: - State Machine

    func testStumpsHitTransitionsToRearranging() {
        let d = makeDetector(minDisarmSeconds: 0.01) // ~2 frames
        // Trigger cliff
        let cliff: [Double] = [0, 0, 1.0, 3.0, 6.0, 10.0, 0.5]
        for (i, e) in cliff.enumerated() { _ = d.feedEnergy(e, atFrame: i) }
        XCTAssertEqual(d.state, .stumpsHit)

        // Feed frames past min disarm
        for i in 0..<10 {
            _ = d.feedEnergy(5.0, atFrame: cliff.count + i)
        }
        XCTAssertEqual(d.state, .rearranging)
    }

    func testRearmsAfterQuietPeriod() {
        let d = makeDetector(minDisarmSeconds: 0.01, rearmQuietSeconds: 0.02)
        // Trigger cliff
        let cliff: [Double] = [0, 0, 1.0, 3.0, 6.0, 10.0, 0.5]
        for (i, e) in cliff.enumerated() { _ = d.feedEnergy(e, atFrame: i) }

        // Past min disarm
        var f = cliff.count
        for _ in 0..<10 { _ = d.feedEnergy(5.0, atFrame: f); f += 1 }
        XCTAssertEqual(d.state, .rearranging)

        // Quiet period → re-arm
        for _ in 0..<20 { _ = d.feedEnergy(0.1, atFrame: f); f += 1 }
        XCTAssertEqual(d.state, .monitoring)
    }

    func testActivityDuringRearrangingResetsQuietStreak() {
        let d = makeDetector(minDisarmSeconds: 0.01, rearmQuietSeconds: 0.02)
        let cliff: [Double] = [0, 0, 1.0, 3.0, 6.0, 10.0, 0.5]
        for (i, e) in cliff.enumerated() { _ = d.feedEnergy(e, atFrame: i) }

        var f = cliff.count
        // Past min disarm
        for _ in 0..<10 { _ = d.feedEnergy(5.0, atFrame: f); f += 1 }

        // Almost quiet enough, then activity
        for _ in 0..<3 { _ = d.feedEnergy(0.1, atFrame: f); f += 1 }
        _ = d.feedEnergy(5.0, atFrame: f); f += 1  // person moves
        XCTAssertEqual(d.state, .rearranging)

        // Now full quiet period
        for _ in 0..<20 { _ = d.feedEnergy(0.1, atFrame: f); f += 1 }
        XCTAssertEqual(d.state, .monitoring)
    }

    func testFullCycleMultipleDeliveries() {
        let d = makeDetector(minDisarmSeconds: 0.01, rearmQuietSeconds: 0.02)
        var f = 0
        var detections = 0

        for _ in 0..<3 {
            // Idle
            for _ in 0..<10 { _ = d.feedEnergy(0.1, atFrame: f); f += 1 }
            // Ball approaching + cliff
            for e in [0.5, 1.0, 3.0, 6.0, 10.0, 0.5] as [Double] {
                if d.feedEnergy(e, atFrame: f) != nil { detections += 1 }
                f += 1
            }
            // Rearrangement activity
            for _ in 0..<15 { _ = d.feedEnergy(5.0, atFrame: f); f += 1 }
            // Quiet → re-arm
            for _ in 0..<20 { _ = d.feedEnergy(0.1, atFrame: f); f += 1 }
        }

        XCTAssertEqual(detections, 3)
        XCTAssertEqual(d.state, .monitoring)
    }

    func testNoFalseTriggersWhenDisarmed() {
        let d = makeDetector(minDisarmSeconds: 0.01, rearmQuietSeconds: 100) // never re-arms in this test
        let cliff: [Double] = [0, 0, 1.0, 3.0, 6.0, 10.0, 0.5]
        for (i, e) in cliff.enumerated() { _ = d.feedEnergy(e, atFrame: i) }

        // Another cliff pattern while disarmed — should not detect
        var f = cliff.count + 20
        for e in [0.0, 0.5, 1.0, 3.0, 6.0, 10.0, 0.5] as [Double] {
            XCTAssertNil(d.feedEnergy(e, atFrame: f))
            f += 1
        }
    }

    // MARK: - State Change Callback

    func testOnStateChangeCallback() {
        let d = makeDetector(minDisarmSeconds: 0.01, rearmQuietSeconds: 0.02)
        var transitions: [CliffDetector.State] = []
        d.onStateChange = { transitions.append($0) }

        let cliff: [Double] = [0, 0, 1.0, 3.0, 6.0, 10.0, 0.5]
        for (i, e) in cliff.enumerated() { _ = d.feedEnergy(e, atFrame: i) }

        var f = cliff.count
        for _ in 0..<10 { _ = d.feedEnergy(5.0, atFrame: f); f += 1 }
        for _ in 0..<20 { _ = d.feedEnergy(0.1, atFrame: f); f += 1 }

        XCTAssertEqual(transitions, [.stumpsHit, .rearranging, .monitoring])
    }

    // MARK: - Reset

    func testResetClearsState() {
        let d = makeDetector()
        let cliff: [Double] = [0, 0, 1.0, 3.0, 6.0, 10.0, 0.5]
        for (i, e) in cliff.enumerated() { _ = d.feedEnergy(e, atFrame: i) }
        XCTAssertEqual(d.state, .stumpsHit)

        d.reset()
        XCTAssertEqual(d.state, .monitoring)
    }

    // MARK: - Speed Helper

    func testSpeedKph() {
        // 163 frames at 240fps, 18.9m → ~100 kph
        let speed = CliffDetector.speedKph(releaseFrame: 100, meetFrame: 263, fps: 240, distanceMetres: 18.9)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!, 100.0, accuracy: 2.0)
    }

    func testSpeedReturnsNilForBadInput() {
        XCTAssertNil(CliffDetector.speedKph(releaseFrame: 200, meetFrame: 100, fps: 240, distanceMetres: 18.9))
        XCTAssertNil(CliffDetector.speedKph(releaseFrame: 100, meetFrame: 100, fps: 240, distanceMetres: 18.9))
    }
}
