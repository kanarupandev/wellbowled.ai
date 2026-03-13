import XCTest
@testable import wellBowled

final class WristVelocityTrackerTests: XCTestCase {

    // MARK: - Spike Detection

    func testDetectsHighVelocitySpike() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 20.0
        tracker.cooldownSeconds = 5.0

        // Simulate a bowling delivery: slow → spike → slow
        // theta changes slowly then suddenly a large angular change (radians)
        let dt = 1.0 / 30.0

        // Pre-delivery: small angle changes
        for i in 0..<30 {
            let time = Double(i) * dt
            let theta = Double(i) * 0.01 // slow movement
            tracker.addSample(theta: theta, at: time)
        }

        // Delivery: sudden large angle change (simulates arm whip)
        let deliveryFrame = 30
        let deliveryTime = Double(deliveryFrame) * dt
        // Central-difference omega uses (next - prev) / (2*dt).
        // Here, delta ≈ 2.0 rad gives omega ≈ 30 rad/s (>20 threshold).
        tracker.addSample(theta: 0.3 + 1.0, at: deliveryTime)
        tracker.addSample(theta: 0.3 + 2.0, at: deliveryTime + dt)
        tracker.addSample(theta: 0.3 + 2.01, at: deliveryTime + 2 * dt)

        XCTAssertGreaterThanOrEqual(tracker.detectedSpikes.count, 1, "Should detect at least one spike")
    }

    func testNoSpikeForSlowMovement() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 20.0

        let dt = 1.0 / 30.0
        // Gentle arm movement — well below threshold
        for i in 0..<60 {
            let time = Double(i) * dt
            let theta = Double(i) * 0.01 // ~0.3 rad/s — walking speed
            tracker.addSample(theta: theta, at: time)
        }

        XCTAssertEqual(tracker.detectedSpikes.count, 0, "Should not detect spikes for slow movement")
    }

    func testCooldownPreventsDoubleDetection() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 20.0
        tracker.cooldownSeconds = 5.0

        let dt = 1.0 / 30.0

        // First spike at t=1s
        for i in 0..<30 {
            tracker.addSample(theta: Double(i) * 0.01, at: Double(i) * dt)
        }
        tracker.addSample(theta: 1.0, at: 1.0)
        tracker.addSample(theta: 2.0, at: 1.0 + dt)
        tracker.addSample(theta: 2.01, at: 1.0 + 2 * dt)

        let spikesAfterFirst = tracker.detectedSpikes.count

        // Second spike at t=2s (within cooldown)
        tracker.addSample(theta: 2.02, at: 2.0)
        tracker.addSample(theta: 4.0, at: 2.0 + dt)
        tracker.addSample(theta: 4.01, at: 2.0 + 2 * dt)

        XCTAssertEqual(tracker.detectedSpikes.count, spikesAfterFirst,
                       "Should NOT detect second spike within cooldown period")
    }

    func testCooldownAllowsDetectionAfterExpiry() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 20.0
        tracker.cooldownSeconds = 5.0

        let dt = 1.0 / 30.0

        // First spike at t=0
        tracker.addSample(theta: 0.0, at: 0.0)
        tracker.addSample(theta: 1.0, at: dt)
        tracker.addSample(theta: 2.0, at: 2 * dt)
        tracker.addSample(theta: 2.01, at: 3 * dt)

        let spikesAfterFirst = tracker.detectedSpikes.count
        XCTAssertGreaterThanOrEqual(spikesAfterFirst, 1)

        // Fill with slow movement until t=6s (past cooldown)
        for i in 4..<200 {
            tracker.addSample(theta: 2.0 + Double(i) * 0.001, at: Double(i) * dt)
        }

        // Second spike at t=7s (well past cooldown)
        tracker.addSample(theta: 4.0, at: 7.0)
        tracker.addSample(theta: 6.0, at: 7.0 + dt)
        tracker.addSample(theta: 6.01, at: 7.0 + 2 * dt)

        XCTAssertGreaterThan(tracker.detectedSpikes.count, spikesAfterFirst,
                             "Should detect second spike after cooldown expires")
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 10.0 // low threshold for easy trigger

        tracker.addSample(theta: 0.0, at: 0.0)
        tracker.addSample(theta: 1.0, at: 0.033)
        tracker.addSample(theta: 2.0, at: 0.066)

        tracker.reset()
        XCTAssertEqual(tracker.detectedSpikes.count, 0)
    }

    // MARK: - Arm Detection

    func testDetectsCorrectBowlingArm() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 10.0

        let dt = 1.0 / 30.0

        // Right arm moves fast, left arm stays still
        tracker.addSample(rightTheta: 0.0, leftTheta: 0.0, at: 0.0)
        tracker.addSample(rightTheta: 1.0, leftTheta: 0.01, at: dt)
        tracker.addSample(rightTheta: 2.0, leftTheta: 0.02, at: 2 * dt)

        if let spike = tracker.detectedSpikes.first {
            XCTAssertEqual(spike.arm, .right)
        }
    }

    func testDetectsLeftArmWhenLeftVelocityDominates() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 150.0 // deg/s

        let dt = 1.0 / 30.0
        tracker.addSample(rightTheta: 0.0, leftTheta: 0.0, at: 0.0)
        tracker.addSample(rightTheta: 0.02, leftTheta: 0.5, at: dt)
        tracker.addSample(rightTheta: 0.04, leftTheta: 1.1, at: 2 * dt)

        XCTAssertEqual(tracker.detectedSpikes.count, 1)
        XCTAssertEqual(tracker.detectedSpikes.first?.arm, .left)
    }

    func testSpikeOmegaIsConvertedToDegreesPerSecondForThresholding() {
        var tracker = WristVelocityTracker(fps: 30.0)
        tracker.threshold = 450.0 // deg/s

        // Central difference around sample[1]:
        // deltaTheta ~= 0.70 rad over 2*dt (~0.0667s) => ~10.5 rad/s => ~601 deg/s.
        let dt = 1.0 / 30.0
        tracker.addSample(theta: 0.0, at: 0.0)
        tracker.addSample(theta: 0.35, at: dt)
        tracker.addSample(theta: 0.70, at: 2 * dt)

        guard let spike = tracker.detectedSpikes.first else {
            XCTFail("Expected spike above 450 deg/s threshold")
            return
        }
        XCTAssertGreaterThan(spike.omega, 450.0)
        XCTAssertLessThan(spike.omega, 900.0)
    }

    // MARK: - Static Utilities

    func testUnwrapThetasHandlesDiscontinuity() {
        // Simulate crossing 2pi boundary: ..., 3.0, -3.0, ...
        // Without unwrapping: delta = -6.0 (wrong)
        // With unwrapping: delta ≈ 0.28 (correct, since 2pi - 6.0 ≈ 0.28)
        let thetas: [Double?] = [2.5, 3.0, -3.0, -2.5]
        let unwrapped = WristVelocityTracker.unwrapThetas(thetas)

        // Should be monotonically increasing (small positive steps)
        for i in 1..<unwrapped.count {
            let delta = unwrapped[i] - unwrapped[i - 1]
            XCTAssertGreaterThan(delta, -0.5, "Unwrapped values should not have large negative jumps")
        }
    }

    func testUnwrapThetasHandlesNils() {
        let thetas: [Double?] = [1.0, nil, 2.0]
        let unwrapped = WristVelocityTracker.unwrapThetas(thetas)
        XCTAssertEqual(unwrapped.count, 3)
    }

    func testComputeAngularVelocities() {
        // Constant angular velocity: theta increases linearly
        let fps = 30.0
        let omega_expected = 10.0 // rad/s
        let dt = 1.0 / fps
        let thetas = (0..<10).map { Double($0) * omega_expected * dt }

        let velocities = WristVelocityTracker.computeAngularVelocities(unwrappedThetas: thetas, fps: fps)

        // Interior points should be close to omega_expected
        for i in 1..<(velocities.count - 1) {
            XCTAssertEqual(velocities[i], omega_expected, accuracy: 0.1,
                           "Interior velocity should match expected angular velocity")
        }
    }

    func testComputeAngularVelocitiesNeedsMinimumSamples() {
        let velocities = WristVelocityTracker.computeAngularVelocities(unwrappedThetas: [1.0, 2.0], fps: 30.0)
        XCTAssertEqual(velocities.count, 2)
        XCTAssertEqual(velocities[0], 0.0)
        XCTAssertEqual(velocities[1], 0.0)
    }
}
