import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import os

private let log = Logger(subsystem: "com.wellbowled", category: "SpeedEstimation")

// MARK: - Errors

enum SpeedEstimationError: LocalizedError {
    case clipLoadFailed
    case noFramesExtracted
    case noBowlerSpike
    case noStrikerSpike
    case invalidTransitTime

    var errorDescription: String? {
        switch self {
        case .clipLoadFailed:
            return "Failed to load the delivery clip for speed analysis."
        case .noFramesExtracted:
            return "No frames could be extracted from the delivery clip."
        case .noBowlerSpike:
            return "No ball motion detected at the bowler end."
        case .noStrikerSpike:
            return "No ball motion detected at the striker end."
        case .invalidTransitTime:
            return "Computed transit time is outside plausible bounds."
        }
    }
}

// MARK: - SpeedEstimationService

/// Estimates ball speed from frame differencing in calibrated stump ROIs.
///
/// Algorithm:
/// 1. Load the clip at native FPS using AVAssetReader.
/// 2. Extract the Y (luminance) plane from each frame as grayscale data.
/// 3. For consecutive frame pairs, compute |frame[n] - frame[n-1]| within each stump ROI.
/// 4. Sum pixels above the motion threshold → "motion energy" per ROI per frame.
/// 5. Search within a time window around the delivery timestamp.
/// 6. Detect bowler-gate spike, then striker-gate spike 0.3–1.0s later.
/// 7. Transit time → speed via `StumpCalibration.speedKph(transitTimeSeconds:)`.
final class SpeedEstimationService: SpeedEstimating {

    // MARK: - SpeedEstimating

    func estimateSpeed(
        clipURL: URL,
        calibration: StumpCalibration,
        deliveryTimestamp: Double
    ) async throws -> SpeedEstimate {
        log.info("Starting speed estimation for clip: \(clipURL.lastPathComponent)")

        // 1. Load clip and extract grayscale frames
        let (frames, fps) = try await extractGrayscaleFrames(from: clipURL)
        guard frames.count >= 2 else {
            log.error("Insufficient frames extracted: \(frames.count)")
            throw SpeedEstimationError.noFramesExtracted
        }

        let frameWidth = frames[0].width
        let frameHeight = frames[0].height
        let frameDuration = 1.0 / fps
        log.info("Extracted \(frames.count) frames at \(fps) fps (\(frameWidth)x\(frameHeight))")

        // 2. Convert normalised ROIs to pixel coordinates
        let bowlerROIPixels = Self.pixelRect(
            from: calibration.bowlerROI,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        let strikerROIPixels = Self.pixelRect(
            from: calibration.strikerROI,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )

        // 3. Compute motion energy for each consecutive frame pair
        let threshold = WBConfig.speedMotionThreshold
        var bowlerEnergies: [Double] = []
        var strikerEnergies: [Double] = []

        for i in 1..<frames.count {
            let prev = frames[i - 1]
            let curr = frames[i]

            let bowlerEnergy = Self.computeMotionEnergy(
                prev: prev.pixels, curr: curr.pixels,
                width: frameWidth, height: frameHeight,
                roi: bowlerROIPixels, threshold: threshold
            )
            let strikerEnergy = Self.computeMotionEnergy(
                prev: prev.pixels, curr: curr.pixels,
                width: frameWidth, height: frameHeight,
                roi: strikerROIPixels, threshold: threshold
            )

            bowlerEnergies.append(bowlerEnergy)
            strikerEnergies.append(strikerEnergy)
        }

        // 4. Determine search window indices
        let searchStart = deliveryTimestamp - WBConfig.speedSearchWindowPreSeconds
        let searchEnd = deliveryTimestamp + WBConfig.speedSearchWindowPostSeconds
        let windowStartIndex = max(Int(searchStart / frameDuration), 0)
        let windowEndIndex = min(Int(searchEnd / frameDuration), bowlerEnergies.count - 1)

        guard windowStartIndex < windowEndIndex else {
            log.error("Search window is empty: [\(windowStartIndex)..\(windowEndIndex)]")
            throw SpeedEstimationError.noBowlerSpike
        }

        // 5. Slice energies to search window
        let bowlerWindow = Array(bowlerEnergies[windowStartIndex...windowEndIndex])
        let strikerWindow = Array(strikerEnergies[windowStartIndex...windowEndIndex])

        // 6. Find bowler-gate spike
        let bowlerNoise = Self.noiseFloor(from: bowlerWindow)
        guard let bowlerSpikeLocal = Self.findMotionSpike(
            energies: bowlerWindow,
            noiseFloor: bowlerNoise,
            spikeMultiplier: 3.0
        ) else {
            log.warning("No bowler-gate motion spike detected")
            throw SpeedEstimationError.noBowlerSpike
        }
        let bowlerSpikeGlobal = windowStartIndex + bowlerSpikeLocal
        let bowlerSpikeTime = Double(bowlerSpikeGlobal + 1) * frameDuration  // +1 because energies are offset by 1 frame

        // 7. Find striker-gate spike (0.3–1.0s after bowler spike)
        let minStrikerDelay = 0.3
        let maxStrikerDelay = 1.0
        let strikerSearchStart = bowlerSpikeTime + minStrikerDelay
        let strikerSearchEnd = bowlerSpikeTime + maxStrikerDelay

        let strikerWindowStartIdx = max(Int(strikerSearchStart / frameDuration) - 1, 0)
        let strikerWindowEndIdx = min(Int(strikerSearchEnd / frameDuration), strikerEnergies.count - 1)

        guard strikerWindowStartIdx < strikerWindowEndIdx else {
            log.warning("Striker search window empty")
            throw SpeedEstimationError.noStrikerSpike
        }

        let strikerSearchSlice = Array(strikerEnergies[strikerWindowStartIdx...strikerWindowEndIdx])
        let strikerNoise = Self.noiseFloor(from: strikerSearchSlice)

        guard let strikerSpikeLocal = Self.findMotionSpike(
            energies: strikerSearchSlice,
            noiseFloor: strikerNoise,
            spikeMultiplier: 3.0
        ) else {
            log.warning("No striker-gate motion spike detected")
            throw SpeedEstimationError.noStrikerSpike
        }
        let strikerSpikeGlobal = strikerWindowStartIdx + strikerSpikeLocal
        let strikerSpikeTime = Double(strikerSpikeGlobal + 1) * frameDuration

        // 8. Compute transit time
        let transitTime = strikerSpikeTime - bowlerSpikeTime
        guard transitTime >= WBConfig.speedMinTransitSeconds,
              transitTime <= WBConfig.speedMaxTransitSeconds else {
            log.error("Transit time \(transitTime)s outside bounds")
            throw SpeedEstimationError.invalidTransitTime
        }

        // 9. Compute speed
        guard let speedKph = calibration.speedKph(transitTimeSeconds: transitTime) else {
            throw SpeedEstimationError.invalidTransitTime
        }

        // 10. Confidence from spike clarity
        let bowlerSpikeEnergy = bowlerWindow[bowlerSpikeLocal]
        let strikerSpikeEnergy = strikerSearchSlice[strikerSpikeLocal]
        let confidence = Self.computeConfidence(
            bowlerSpikeEnergy: bowlerSpikeEnergy,
            strikerSpikeEnergy: strikerSpikeEnergy,
            bowlerNoiseFloor: bowlerNoise,
            strikerNoiseFloor: strikerNoise
        )

        let errorMargin = calibration.speedErrorKph(transitTimeSeconds: transitTime)

        log.info("Speed estimate: \(speedKph, privacy: .public) kph, confidence: \(confidence, privacy: .public)")

        return SpeedEstimate(
            kph: speedKph,
            confidence: confidence,
            method: .frameDifferencing,
            transitTimeSeconds: transitTime,
            errorMarginKph: errorMargin,
            bowlerFrameIndex: bowlerSpikeGlobal + 1,  // +1 to convert from diff index to frame index
            strikerFrameIndex: strikerSpikeGlobal + 1
        )
    }

    // MARK: - Static Helpers (Testable)

    /// Compute motion energy between two grayscale frame buffers within a pixel-space ROI.
    /// Returns fraction of pixels that exceed the motion threshold (0.0–1.0).
    static func computeMotionEnergy(
        prev: UnsafeBufferPointer<UInt8>,
        curr: UnsafeBufferPointer<UInt8>,
        width: Int,
        height: Int,
        roi: CGRect,
        threshold: Double
    ) -> Double {
        let roiMinX = max(Int(roi.minX), 0)
        let roiMaxX = min(Int(roi.maxX), width)
        let roiMinY = max(Int(roi.minY), 0)
        let roiMaxY = min(Int(roi.maxY), height)

        let roiWidth = roiMaxX - roiMinX
        let roiHeight = roiMaxY - roiMinY
        let roiPixelCount = roiWidth * roiHeight

        guard roiPixelCount > 0 else { return 0.0 }

        let thresholdUInt8 = UInt8(clamping: Int(threshold))
        var aboveThresholdCount = 0

        for y in roiMinY..<roiMaxY {
            let rowOffset = y * width
            for x in roiMinX..<roiMaxX {
                let idx = rowOffset + x
                guard idx < prev.count, idx < curr.count else { continue }
                let diff: UInt8
                if curr[idx] > prev[idx] {
                    diff = curr[idx] - prev[idx]
                } else {
                    diff = prev[idx] - curr[idx]
                }
                if diff > thresholdUInt8 {
                    aboveThresholdCount += 1
                }
            }
        }

        return Double(aboveThresholdCount) / Double(roiPixelCount)
    }

    /// Find the first motion spike in a time series of energy values.
    /// Returns the index of the first value that exceeds `noiseFloor * spikeMultiplier`.
    static func findMotionSpike(
        energies: [Double],
        noiseFloor: Double,
        spikeMultiplier: Double = 3.0
    ) -> Int? {
        let spikeThreshold = noiseFloor * spikeMultiplier
        for (index, energy) in energies.enumerated() {
            if energy > spikeThreshold {
                return index
            }
        }
        return nil
    }

    /// Compute noise floor as the median of energy values.
    static func noiseFloor(from energies: [Double]) -> Double {
        guard !energies.isEmpty else { return 0.0 }
        let sorted = energies.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    // MARK: - Private Helpers

    /// Convert a normalised rect (0–1) to pixel coordinates.
    static func pixelRect(from normalised: CGRect, frameWidth: Int, frameHeight: Int) -> CGRect {
        CGRect(
            x: normalised.origin.x * CGFloat(frameWidth),
            y: normalised.origin.y * CGFloat(frameHeight),
            width: normalised.width * CGFloat(frameWidth),
            height: normalised.height * CGFloat(frameHeight)
        )
    }

    /// Compute confidence (0–1) from spike-to-noise ratios at both gates.
    private static func computeConfidence(
        bowlerSpikeEnergy: Double,
        strikerSpikeEnergy: Double,
        bowlerNoiseFloor: Double,
        strikerNoiseFloor: Double
    ) -> Double {
        let bowlerSNR = bowlerNoiseFloor > 0 ? bowlerSpikeEnergy / bowlerNoiseFloor : 10.0
        let strikerSNR = strikerNoiseFloor > 0 ? strikerSpikeEnergy / strikerNoiseFloor : 10.0

        // Average SNR, then map to 0–1 with diminishing returns.
        // SNR of 3 (minimum spike) → ~0.5, SNR of 10+ → ~0.9+
        let avgSNR = (bowlerSNR + strikerSNR) / 2.0
        let confidence = min(1.0, avgSNR / 12.0)
        return max(0.0, confidence)
    }

    // MARK: - Frame Extraction

    /// Container for a single grayscale frame's pixel data.
    struct GrayscaleFrame {
        let pixels: UnsafeBufferPointer<UInt8>
        let width: Int
        let height: Int
        /// Backing allocation — must remain alive while `pixels` is in use.
        fileprivate let backing: Data
    }

    /// Extract grayscale frames from a video clip using AVAssetReader.
    /// Returns the frames and the actual FPS of the video track.
    private func extractGrayscaleFrames(from url: URL) async throws -> ([GrayscaleFrame], Double) {
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SpeedEstimationError.clipLoadFailed
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let fps = Double(nominalFrameRate)
        guard fps > 0 else {
            throw SpeedEstimationError.clipLoadFailed
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            log.error("AVAssetReader init failed: \(error.localizedDescription)")
            throw SpeedEstimationError.clipLoadFailed
        }

        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw SpeedEstimationError.clipLoadFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            log.error("AVAssetReader failed to start: \(reader.error?.localizedDescription ?? "unknown")")
            throw SpeedEstimationError.clipLoadFailed
        }

        var frames: [GrayscaleFrame] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            // Extract Y plane (plane 0) from the biplanar YCbCr buffer
            guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { continue }
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let planeWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

            // Copy the Y plane into a contiguous Data buffer (stride-aware)
            var data = Data(count: planeWidth * planeHeight)
            data.withUnsafeMutableBytes { destPtr in
                guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let src = baseAddress.assumingMemoryBound(to: UInt8.self)
                for row in 0..<planeHeight {
                    let srcRow = src.advanced(by: row * bytesPerRow)
                    let destRow = dest.advanced(by: row * planeWidth)
                    destRow.update(from: srcRow, count: planeWidth)
                }
            }

            let frame = data.withUnsafeBytes { rawBuffer in
                let typedBuffer = rawBuffer.bindMemory(to: UInt8.self)
                return GrayscaleFrame(
                    pixels: UnsafeBufferPointer(start: typedBuffer.baseAddress, count: typedBuffer.count),
                    width: planeWidth,
                    height: planeHeight,
                    backing: data
                )
            }
            frames.append(frame)
        }

        if reader.status == .failed {
            log.error("AVAssetReader failed: \(reader.error?.localizedDescription ?? "unknown")")
            throw SpeedEstimationError.clipLoadFailed
        }

        return (frames, fps)
    }
}
