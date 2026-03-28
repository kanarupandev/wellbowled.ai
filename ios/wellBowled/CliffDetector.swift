import Foundation

struct CliffDetection {
    let meetFrame: Int
    let meetEnergy: Double
    let cliffRatio: Double
}

/// Detects stumps being hit, then waits for rearrangement before re-arming.
///
/// States:
///   monitoring → stumps hit (cliff) → waiting for rearrangement → monitoring
///
/// Callers observe `state` changes to drive TTS and UI:
///   .monitoring  → green dot, "Monitoring stumps"
///   .stumpsHit   → amber, "Stumps! Rearrange stumps"
///   .rearranging → amber, waiting for scene to settle
///   .monitoring  → green dot, "Ready"
final class CliffDetector {

    enum State: Equatable {
        case monitoring
        case stumpsHit    // just detected, brief hold
        case rearranging  // waiting for scene to settle
    }

    // MARK: - Config

    let fps: Double
    let cliffDropThreshold: Double
    let minPreEnergy: Double
    let risingWindow: Int
    let minDisarmFrames: Int       // minimum frames before checking for re-arm (3s)
    let rearmQuietFrames: Int      // consecutive quiet frames to re-arm (3s)
    let maxDisarmFrames: Int       // force re-arm safety valve (120s)
    let quietThreshold: Double     // energy below this = quiet

    // MARK: - State

    private(set) var state: State = .monitoring
    private var energyBuffer: [(frame: Int, energy: Double)] = []
    private let bufferSize: Int
    private var disarmedAtFrame: Int = 0
    private var quietStreak: Int = 0
    /// Called on state transitions so the ViewModel can react.
    var onStateChange: ((State) -> Void)?

    init(
        fps: Double,
        cliffDropThreshold: Double = 0.4,  // 60% drop triggers (was 70%) — favor catching over filtering
        minPreEnergy: Double = 1.5,      // lower bar — don't miss slow deliveries
        risingWindow: Int = 2,           // fewer rising frames needed — faster triggers
        minDisarmSeconds: Double = 1.0,
        rearmQuietSeconds: Double = 1.0,
        maxDisarmSeconds: Double = 120.0,
        quietThreshold: Double = 0.8
    ) {
        self.fps = fps
        self.cliffDropThreshold = cliffDropThreshold
        self.minPreEnergy = minPreEnergy
        self.risingWindow = risingWindow
        self.minDisarmFrames = Int(fps * minDisarmSeconds)
        self.rearmQuietFrames = Int(fps * rearmQuietSeconds)
        self.maxDisarmFrames = Int(fps * maxDisarmSeconds)
        self.quietThreshold = quietThreshold
        self.bufferSize = Int(fps * 3)
    }

    @discardableResult
    func feedEnergy(_ energy: Double, atFrame frame: Int) -> CliffDetection? {
        energyBuffer.append((frame: frame, energy: energy))
        if energyBuffer.count > bufferSize {
            energyBuffer.removeFirst()
        }

        switch state {
        case .monitoring:
            guard energyBuffer.count >= risingWindow + 2 else { return nil }
            return checkCliff(atFrame: frame)

        case .stumpsHit:
            // Brief hold — transition to rearranging after min disarm
            if frame - disarmedAtFrame >= minDisarmFrames {
                transition(to: .rearranging)
            }
            return nil

        case .rearranging:
            // Safety: force re-arm after max disarm time
            if frame - disarmedAtFrame >= maxDisarmFrames {
                transition(to: .monitoring)
                return nil
            }
            // Count consecutive quiet frames
            if energy < quietThreshold {
                quietStreak += 1
                if quietStreak >= rearmQuietFrames {
                    energyBuffer.removeAll()
                    transition(to: .monitoring)
                }
            } else {
                quietStreak = 0
            }
            return nil
        }
    }

    func reset() {
        energyBuffer.removeAll()
        quietStreak = 0
        disarmedAtFrame = 0
        transition(to: .monitoring)
    }

    static func speedKph(
        releaseFrame: Int,
        meetFrame: Int,
        fps: Double,
        distanceMetres: Double
    ) -> Double? {
        let frameDiff = meetFrame - releaseFrame
        guard frameDiff > 0 else { return nil }
        let transitTime = Double(frameDiff) / fps
        guard transitTime >= WBConfig.speedMinTransitSeconds,
              transitTime <= WBConfig.speedMaxTransitSeconds else {
            return nil
        }
        let speed = (distanceMetres / transitTime) * 3.6
        guard speed >= 30, speed <= 200 else { return nil }
        return speed
    }

    // MARK: - Private

    private func transition(to newState: State) {
        guard state != newState else { return }
        state = newState
        quietStreak = 0
        onStateChange?(newState)
    }

    private func checkCliff(atFrame frame: Int) -> CliffDetection? {
        let n = energyBuffer.count
        guard n >= 3 else { return nil }

        let current = energyBuffer[n - 2]
        let next = energyBuffer[n - 1]

        guard current.energy >= minPreEnergy else { return nil }
        guard next.energy <= current.energy * cliffDropThreshold else { return nil }

        let windowStart = max(0, n - risingWindow - 2)
        let window = energyBuffer[windowStart..<(n - 1)]
        guard window.count >= risingWindow else { return nil }

        let windowEnergies = window.map(\.energy)
        var risingCount = 0
        for i in 1..<windowEnergies.count {
            if windowEnergies[i] > windowEnergies[i - 1] {
                risingCount += 1
            }
        }
        // At least 1 rising transition — favor sensitivity over precision
        guard risingCount >= 1 else { return nil }

        let preMean = windowEnergies.dropLast().reduce(0, +) / Double(max(windowEnergies.count - 1, 1))
        guard preMean >= minPreEnergy * 0.5 else { return nil }

        let cliffRatio = current.energy / max(next.energy, 0.01)

        disarmedAtFrame = frame
        transition(to: .stumpsHit)

        return CliffDetection(
            meetFrame: current.frame,
            meetEnergy: current.energy,
            cliffRatio: cliffRatio
        )
    }
}
