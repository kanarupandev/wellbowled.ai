import Foundation

/// Pure algorithm for detecting bowling delivery spikes from wrist angular velocity.
/// Separated from MediaPipe for testability.
///
/// Algorithm (ported from experiments/delivery_detection/003_mediapipe_ground_truth.py):
/// 1. Track wrist angle relative to shoulder: theta = atan2(dx, dy)
/// 2. Unwrap theta to handle 2pi crossings
/// 3. Compute angular velocity: omega = (theta[i+1] - theta[i-1]) / (2 * dt)
/// 4. Detect spikes above threshold with cooldown
struct WristVelocityTracker {

    struct Spike {
        let timestamp: Double
        let omega: Double
        let arm: BowlingArm
    }

    /// Single angle sample at a point in time.
    struct ThetaSample {
        let theta: Double?
        let time: Double
    }

    // MARK: - Configuration

    var threshold: Double = WBConfig.wristVelocityThreshold
    var cooldownSeconds: Double = WBConfig.deliveryCooldown

    // MARK: - State

    private let fps: Double
    private var rightThetas: [ThetaSample] = []
    private var leftThetas: [ThetaSample] = []
    private var lastSpikeTime: Double = -999
    private(set) var detectedSpikes: [Spike] = []

    init(fps: Double) {
        self.fps = fps
    }

    // MARK: - Public API

    /// Add a wrist angle sample for both arms.
    /// Call this for every processed frame.
    mutating func addSample(
        rightTheta: Double?,
        leftTheta: Double?,
        at time: Double
    ) {
        rightThetas.append(ThetaSample(theta: rightTheta, time: time))
        leftThetas.append(ThetaSample(theta: leftTheta, time: time))
        checkForSpike()
    }

    /// Convenience: single-arm tracking (for tests or when only one arm visible)
    mutating func addSample(theta: Double?, at time: Double) {
        addSample(rightTheta: theta, leftTheta: nil, at: time)
    }

    mutating func reset() {
        rightThetas.removeAll()
        leftThetas.removeAll()
        detectedSpikes.removeAll()
        lastSpikeTime = -999
    }

    // MARK: - Spike Detection

    private mutating func checkForSpike() {
        // Need at least 3 samples for central difference
        guard rightThetas.count >= 3 else { return }

        let n = rightThetas.count

        // Compute omega for the most recent point using central difference
        let rOmega = computeOmegaAtIndex(n - 2, thetas: rightThetas)
        let lOmega = computeOmegaAtIndex(n - 2, thetas: leftThetas)

        // App thresholds are tuned in degrees/sec from experiments.
        // Convert internal rad/sec derivative to deg/sec before thresholding/classification.
        let radToDeg = 180.0 / Double.pi
        let absR = abs(rOmega) * radToDeg
        let absL = abs(lOmega) * radToDeg
        let peakOmega = max(absR, absL)
        let arm: BowlingArm = absR >= absL ? .right : .left
        let time = rightThetas[n - 2].time

        if peakOmega > threshold && (time - lastSpikeTime) > cooldownSeconds {
            lastSpikeTime = time
            detectedSpikes.append(Spike(
                timestamp: time,
                omega: peakOmega,
                arm: arm
            ))
        }
    }

    private func computeOmegaAtIndex(_ i: Int, thetas: [ThetaSample]) -> Double {
        guard i > 0, i < thetas.count - 1 else { return 0 }
        guard let prev = thetas[i - 1].theta, let next = thetas[i + 1].theta else { return 0 }

        // Unwrap delta
        var delta = next - prev
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        let dt = thetas[i + 1].time - thetas[i - 1].time
        guard dt > 0 else { return 0 }

        return delta / dt
    }

    // MARK: - Static Utilities (for batch processing / tests)

    /// Unwrap an array of theta values to remove 2pi discontinuities.
    static func unwrapThetas(_ thetas: [Double?]) -> [Double] {
        guard let first = thetas.first else { return [] }
        var unwrapped = [first ?? 0]

        for i in 1..<thetas.count {
            guard let current = thetas[i], let previous = thetas[i - 1] else {
                unwrapped.append(unwrapped.last ?? 0)
                continue
            }
            var delta = current - previous
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            unwrapped.append(unwrapped.last! + delta)
        }
        return unwrapped
    }

    /// Compute angular velocities using central difference.
    static func computeAngularVelocities(unwrappedThetas: [Double], fps: Double) -> [Double] {
        let n = unwrappedThetas.count
        guard n >= 3 else { return Array(repeating: 0, count: n) }

        let dt = 1.0 / fps
        var omega = [0.0]
        for i in 1..<(n - 1) {
            omega.append((unwrappedThetas[i + 1] - unwrappedThetas[i - 1]) / (2 * dt))
        }
        omega.append(0.0)
        return omega
    }
}
