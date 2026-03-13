import CoreGraphics
import XCTest
@testable import wellBowled

final class DeliveryPoseSelectorTests: XCTestCase {

    func testSelectsLargestShoulderSpanWhenNoLock() {
        let selector = DeliveryPoseSelector(minShoulderSpan: 0.05, lockMaxCenterDrift: 0.2, driftPenalty: 0.35)
        let near = makeCandidate(centerX: 0.35, shoulderSpan: 0.11)
        let wide = makeCandidate(centerX: 0.70, shoulderSpan: 0.22)

        let selected = selector.select(from: [near, wide], lockCenter: nil)

        guard let selected else {
            return XCTFail("Expected a selected candidate")
        }
        XCTAssertEqual(selected.candidate.shoulderCenter.x, wide.shoulderCenter.x, accuracy: 0.0001)
    }

    func testPrefersLockedCandidateWhenWithinDriftWindow() {
        let selector = DeliveryPoseSelector(minShoulderSpan: 0.05, lockMaxCenterDrift: 0.10, driftPenalty: 0.35)
        let lockCenter = CGPoint(x: 0.32, y: 0.50)

        let locked = makeCandidate(centerX: 0.34, shoulderSpan: 0.12)
        let widerButFar = makeCandidate(centerX: 0.82, shoulderSpan: 0.24)

        let selected = selector.select(from: [locked, widerButFar], lockCenter: lockCenter)

        guard let selected else {
            return XCTFail("Expected a selected candidate")
        }
        XCTAssertEqual(selected.candidate.shoulderCenter.x, locked.shoulderCenter.x, accuracy: 0.0001)
        XCTAssertNotNil(selected.distanceFromLock)
        XCTAssertLessThanOrEqual(selected.distanceFromLock ?? .infinity, 0.10)
    }

    func testFallsBackWhenNoCandidateInsideLockWindow() {
        let selector = DeliveryPoseSelector(minShoulderSpan: 0.05, lockMaxCenterDrift: 0.02, driftPenalty: 0.1)
        let lockCenter = CGPoint(x: 0.15, y: 0.50)

        let first = makeCandidate(centerX: 0.50, shoulderSpan: 0.10)
        let second = makeCandidate(centerX: 0.80, shoulderSpan: 0.20)

        let selected = selector.select(from: [first, second], lockCenter: lockCenter)

        guard let selected else {
            return XCTFail("Expected a selected candidate")
        }
        XCTAssertEqual(selected.candidate.shoulderCenter.x, second.shoulderCenter.x, accuracy: 0.0001)
    }

    func testRejectsCandidatesBelowShoulderSpanThreshold() {
        let selector = DeliveryPoseSelector(minShoulderSpan: 0.12, lockMaxCenterDrift: 0.2, driftPenalty: 0.35)
        let tooSmall = makeCandidate(centerX: 0.5, shoulderSpan: 0.08)

        let selected = selector.select(from: [tooSmall], lockCenter: nil)

        XCTAssertNil(selected)
    }

    func testIsDeterministicWhenScoresTie() {
        let selector = DeliveryPoseSelector(minShoulderSpan: 0.05, lockMaxCenterDrift: 0.2, driftPenalty: 0.35)
        let left = makeCandidate(centerX: 0.40, shoulderSpan: 0.18)
        let right = makeCandidate(centerX: 0.60, shoulderSpan: 0.18)

        let first = selector.select(from: [left, right], lockCenter: nil)
        let second = selector.select(from: [left, right], lockCenter: nil)

        guard let first, let second else {
            return XCTFail("Expected deterministic non-nil selection")
        }
        XCTAssertEqual(first.candidate.shoulderCenter.x, second.candidate.shoulderCenter.x, accuracy: 0.0001)
    }

    private func makeCandidate(
        centerX: Double,
        centerY: Double = 0.50,
        shoulderSpan: Double,
        wristYOffset: Double = -0.15
    ) -> DeliveryPoseCandidate {
        let leftShoulder = CGPoint(x: centerX - shoulderSpan * 0.5, y: centerY)
        let rightShoulder = CGPoint(x: centerX + shoulderSpan * 0.5, y: centerY)
        return DeliveryPoseCandidate(
            rightShoulder: rightShoulder,
            rightWrist: CGPoint(x: rightShoulder.x, y: centerY + wristYOffset),
            leftShoulder: leftShoulder,
            leftWrist: CGPoint(x: leftShoulder.x, y: centerY + wristYOffset)
        )
    }
}
