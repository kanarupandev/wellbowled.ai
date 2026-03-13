import CoreGraphics
import Foundation

/// Minimal pose payload required for delivery detection.
struct DeliveryPoseCandidate {
    let rightShoulder: CGPoint
    let rightWrist: CGPoint
    let leftShoulder: CGPoint
    let leftWrist: CGPoint

    var shoulderCenter: CGPoint {
        CGPoint(
            x: (rightShoulder.x + leftShoulder.x) * 0.5,
            y: (rightShoulder.y + leftShoulder.y) * 0.5
        )
    }

    var shoulderSpan: Double {
        let dx = Double(rightShoulder.x - leftShoulder.x)
        let dy = Double(rightShoulder.y - leftShoulder.y)
        return hypot(dx, dy)
    }

    var rightTheta: Double {
        atan2(
            Double(rightWrist.x - rightShoulder.x),
            Double(rightWrist.y - rightShoulder.y)
        )
    }

    var leftTheta: Double {
        atan2(
            Double(leftWrist.x - leftShoulder.x),
            Double(leftWrist.y - leftShoulder.y)
        )
    }
}

struct DeliveryPoseSelection {
    let candidate: DeliveryPoseCandidate
    let distanceFromLock: Double?
}

/// Selects a stable bowler pose across frames when multiple people appear.
struct DeliveryPoseSelector {
    var minShoulderSpan: Double = WBConfig.deliveryPoseMinShoulderSpan
    var lockMaxCenterDrift: Double = WBConfig.deliveryPoseLockMaxCenterDrift
    var driftPenalty: Double = WBConfig.deliveryPoseLockDriftPenalty

    func select(from candidates: [DeliveryPoseCandidate], lockCenter: CGPoint?) -> DeliveryPoseSelection? {
        let valid = candidates.filter { $0.shoulderSpan >= minShoulderSpan }
        guard !valid.isEmpty else { return nil }

        let scored = valid.map { candidate -> (candidate: DeliveryPoseCandidate, distance: Double?, score: Double) in
            let distance: Double?
            if let lockCenter {
                let dx = Double(candidate.shoulderCenter.x - lockCenter.x)
                let dy = Double(candidate.shoulderCenter.y - lockCenter.y)
                distance = hypot(dx, dy)
            } else {
                distance = nil
            }

            let penalty = (distance ?? 0) * driftPenalty
            return (candidate, distance, candidate.shoulderSpan - penalty)
        }

        let pool: [(candidate: DeliveryPoseCandidate, distance: Double?, score: Double)]
        if lockCenter != nil {
            let locked = scored.filter { ($0.distance ?? .infinity) <= lockMaxCenterDrift }
            pool = locked.isEmpty ? scored : locked
        } else {
            pool = scored
        }

        guard let best = pool.max(by: compare) else { return nil }
        return DeliveryPoseSelection(candidate: best.candidate, distanceFromLock: best.distance)
    }

    private func compare(
        _ lhs: (candidate: DeliveryPoseCandidate, distance: Double?, score: Double),
        _ rhs: (candidate: DeliveryPoseCandidate, distance: Double?, score: Double)
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        if lhs.candidate.shoulderSpan != rhs.candidate.shoulderSpan {
            return lhs.candidate.shoulderSpan < rhs.candidate.shoulderSpan
        }
        let lDist = lhs.distance ?? .infinity
        let rDist = rhs.distance ?? .infinity
        if lDist != rDist { return lDist > rDist }
        if lhs.candidate.shoulderCenter.x != rhs.candidate.shoulderCenter.x {
            return lhs.candidate.shoulderCenter.x > rhs.candidate.shoulderCenter.x
        }
        return lhs.candidate.shoulderCenter.y > rhs.candidate.shoulderCenter.y
    }
}
