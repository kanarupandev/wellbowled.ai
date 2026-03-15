import CoreGraphics
import Foundation

// MARK: - Stump Calibration

/// Calibration data from detected stump positions used for frame-differencing speed estimation.
/// Stored per-session. Pixel coordinates are relative to the camera's native resolution.
struct StumpCalibration: Codable, Equatable {

    /// Normalized centre of the bowler-end stump ROI (0–1 in both axes).
    let bowlerStumpCenter: CGPoint

    /// Normalized centre of the striker-end stump ROI (0–1 in both axes).
    let strikerStumpCenter: CGPoint

    /// Camera frame dimensions at calibration time (pixels).
    let frameWidth: Int
    let frameHeight: Int

    /// Recording FPS at calibration time.
    let recordingFPS: Int

    /// Timestamp when calibration was locked.
    let calibratedAt: Date

    /// Whether the user placed stumps manually (tap fallback) vs vision-detected.
    let isManualPlacement: Bool

    // MARK: - Computed

    /// Pitch length in metres (law-of-cricket standard).
    static let pitchLengthMetres: Double = WBConfig.pitchLengthMetres

    /// Euclidean pixel distance between the two stump centres.
    var stumpSeparationPixels: Double {
        let dx = Double(bowlerStumpCenter.x - strikerStumpCenter.x) * Double(frameWidth)
        let dy = Double(bowlerStumpCenter.y - strikerStumpCenter.y) * Double(frameHeight)
        return sqrt(dx * dx + dy * dy)
    }

    /// Pixels per metre derived from stump separation and known pitch length.
    var pixelsPerMetre: Double {
        guard stumpSeparationPixels > 0 else { return 0 }
        return stumpSeparationPixels / Self.pitchLengthMetres
    }

    /// Whether this calibration has valid, usable data.
    var isValid: Bool {
        stumpSeparationPixels > 0 &&
        frameWidth > 0 &&
        frameHeight > 0 &&
        recordingFPS > 0 &&
        bowlerStumpCenter != strikerStumpCenter
    }

    /// Bowler-end ROI rect (normalized 0–1) for frame differencing.
    var bowlerROI: CGRect {
        roiRect(around: bowlerStumpCenter)
    }

    /// Striker-end ROI rect (normalized 0–1) for frame differencing.
    var strikerROI: CGRect {
        roiRect(around: strikerStumpCenter)
    }

    /// Compute speed in kph from a transit time (seconds) between bowler and striker gates.
    /// Returns nil if transit time is outside sane bounds.
    func speedKph(transitTimeSeconds: Double) -> Double? {
        guard transitTimeSeconds >= WBConfig.speedMinTransitSeconds,
              transitTimeSeconds <= WBConfig.speedMaxTransitSeconds else {
            return nil
        }
        return (Self.pitchLengthMetres / transitTimeSeconds) * 3.6
    }

    /// Theoretical speed error (±kph) for a given frame-count uncertainty at this FPS.
    func speedErrorKph(transitTimeSeconds: Double, frameUncertainty: Int = 2) -> Double? {
        guard let nominalSpeed = speedKph(transitTimeSeconds: transitTimeSeconds),
              recordingFPS > 0 else {
            return nil
        }
        let dt = Double(frameUncertainty) / Double(recordingFPS)
        guard let fastSpeed = speedKph(transitTimeSeconds: max(transitTimeSeconds - dt, WBConfig.speedMinTransitSeconds)),
              let slowSpeed = speedKph(transitTimeSeconds: min(transitTimeSeconds + dt, WBConfig.speedMaxTransitSeconds)) else {
            return nil
        }
        return max(abs(fastSpeed - nominalSpeed), abs(nominalSpeed - slowSpeed))
    }

    // MARK: - Private

    private func roiRect(around center: CGPoint) -> CGRect {
        let halfW = WBConfig.speedROIWidthRatio / 2
        let halfH = WBConfig.calibrationBoxHeightRatio / 2
        return CGRect(
            x: max(Double(center.x) - Double(halfW), 0),
            y: max(Double(center.y) - Double(halfH), 0),
            width: Double(WBConfig.speedROIWidthRatio),
            height: Double(WBConfig.calibrationBoxHeightRatio)
        )
    }
}

// MARK: - Speed Estimate

/// Result of on-device frame-differencing speed estimation for one delivery.
struct SpeedEstimate: Codable, Equatable {
    let kph: Double
    let confidence: Double
    let method: SpeedEstimationMethod
    let transitTimeSeconds: Double
    let errorMarginKph: Double?

    /// Bowler-gate frame index where ball motion was first detected.
    let bowlerFrameIndex: Int?
    /// Striker-gate frame index where ball motion was detected.
    let strikerFrameIndex: Int?
}
