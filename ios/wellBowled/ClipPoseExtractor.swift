import AVFoundation
import Foundation
import os

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

enum PoseExtractionError: LocalizedError {
    case mediaPipeUnavailable
    case modelMissing
    case noVideoTrack
    case readerFailed
    case noLandmarksDetected(sampledFrames: Int)

    var errorDescription: String? {
        switch self {
        case .mediaPipeUnavailable:
            return "MediaPipe Tasks Vision is unavailable on this build target."
        case .modelMissing:
            return "pose_landmarker.task is missing from app bundle."
        case .noVideoTrack:
            return "No video track found in clip."
        case .readerFailed:
            return "Failed to decode clip frames for pose extraction."
        case .noLandmarksDetected(let sampledFrames):
            return "No confident pose landmarks detected (\(sampledFrames) sampled frames)."
        }
    }
}

final class ClipPoseExtractor {
    private static let log = Logger(subsystem: "com.wellbowled", category: "PoseExtractor")

    private static let landmarkNames: [String] = [
        "NOSE", "LEFT_EYE_INNER", "LEFT_EYE", "LEFT_EYE_OUTER", "RIGHT_EYE_INNER", "RIGHT_EYE", "RIGHT_EYE_OUTER",
        "LEFT_EAR", "RIGHT_EAR", "MOUTH_LEFT", "MOUTH_RIGHT", "LEFT_SHOULDER", "RIGHT_SHOULDER",
        "LEFT_ELBOW", "RIGHT_ELBOW", "LEFT_WRIST", "RIGHT_WRIST", "LEFT_PINKY", "RIGHT_PINKY",
        "LEFT_INDEX", "RIGHT_INDEX", "LEFT_THUMB", "RIGHT_THUMB", "LEFT_HIP", "RIGHT_HIP",
        "LEFT_KNEE", "RIGHT_KNEE", "LEFT_ANKLE", "RIGHT_ANKLE", "LEFT_HEEL", "RIGHT_HEEL",
        "LEFT_FOOT_INDEX", "RIGHT_FOOT_INDEX"
    ]

    #if canImport(MediaPipeTasksVision)
    private enum ExtractionProfile: String {
        case primary
        case fallback
    }

    private struct DetectionPassResult {
        let frames: [FramePoseLandmarks]
        let sampledFrameCount: Int
    }

    private lazy var primaryPoseLandmarker: PoseLandmarker? = {
        makePoseLandmarker(profile: .primary)
    }()

    private lazy var fallbackPoseLandmarker: PoseLandmarker? = {
        makePoseLandmarker(profile: .fallback)
    }()

    private func makePoseLandmarker(profile: ExtractionProfile) -> PoseLandmarker? {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker", ofType: "task") else {
            Self.log.error("pose_landmarker.task NOT found in bundle for \(profile.rawValue, privacy: .public) profile")
            print("🦴 [PoseExtract] Model NOT FOUND in bundle")
            return nil
        }
        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .video
            switch profile {
            case .primary:
                options.numPoses = 1
                options.minPoseDetectionConfidence = 0.35
                options.minTrackingConfidence = 0.3
            case .fallback:
                // High-recall fallback for far/fast bowlers and noisy backgrounds.
                options.numPoses = 2
                options.minPoseDetectionConfidence = 0.2
                options.minTrackingConfidence = 0.1
            }
            let landmarker = try PoseLandmarker(options: options)
            Self.log.info("PoseLandmarker initialized: profile=\(profile.rawValue, privacy: .public), model=\(modelPath, privacy: .public)")
            return landmarker
        } catch {
            Self.log.error("PoseLandmarker init failed for \(profile.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    #endif

    func extractFrames(from clipURL: URL, targetFPS: Double) async throws -> [FramePoseLandmarks] {
        #if canImport(MediaPipeTasksVision)
        print("🦴 [PoseExtract] START: clip=\(clipURL.lastPathComponent), targetFPS=\(targetFPS)")
        Self.log.debug("Pose extraction started: clip=\(clipURL.lastPathComponent, privacy: .public), targetFPS=\(targetFPS, privacy: .public)")
        guard let primaryLandmarker = primaryPoseLandmarker else {
            if Bundle.main.path(forResource: "pose_landmarker", ofType: "task") == nil {
                Self.log.error("Pose extraction failed: pose_landmarker.task missing")
                throw PoseExtractionError.modelMissing
            }
            Self.log.error("Pose extraction failed: MediaPipe unavailable")
            throw PoseExtractionError.mediaPipeUnavailable
        }

        let asset = AVURLAsset(url: clipURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            Self.log.error("Pose extraction failed: no video track")
            throw PoseExtractionError.noVideoTrack
        }

        let primaryPass = try runDetectionPass(
            asset: asset,
            track: track,
            landmarker: primaryLandmarker,
            targetFPS: targetFPS,
            profile: .primary
        )

        if !primaryPass.frames.isEmpty {
            print("🦴 [PoseExtract] PRIMARY OK: \(primaryPass.frames.count) frames from \(primaryPass.sampledFrameCount) sampled")
            Self.log.debug("Pose extraction completed (primary): frames=\(primaryPass.frames.count, privacy: .public), sampled=\(primaryPass.sampledFrameCount, privacy: .public)")
            return primaryPass.frames
        }

        guard let fallbackLandmarker = fallbackPoseLandmarker else {
            Self.log.warning("Pose extraction fallback unavailable; no landmarks detected in primary pass")
            throw PoseExtractionError.noLandmarksDetected(sampledFrames: primaryPass.sampledFrameCount)
        }

        Self.log.warning("Primary pose pass detected 0 frames; running fallback pass")
        let fallbackTargetFPS = max(targetFPS, 15.0)
        let fallbackPass = try runDetectionPass(
            asset: asset,
            track: track,
            landmarker: fallbackLandmarker,
            targetFPS: fallbackTargetFPS,
            profile: .fallback
        )

        if !fallbackPass.frames.isEmpty {
            Self.log.debug("Pose extraction completed (fallback): frames=\(fallbackPass.frames.count, privacy: .public), sampled=\(fallbackPass.sampledFrameCount, privacy: .public)")
            return fallbackPass.frames
        }

        let sampledTotal = primaryPass.sampledFrameCount + fallbackPass.sampledFrameCount
        Self.log.warning("Pose extraction ended with no landmarks: sampledTotal=\(sampledTotal, privacy: .public)")
        throw PoseExtractionError.noLandmarksDetected(sampledFrames: sampledTotal)
        #else
        print("🦴 [PoseExtract] UNAVAILABLE: MediaPipeTasksVision not importable")
        Self.log.error("Pose extraction unavailable: MediaPipeTasksVision not importable")
        throw PoseExtractionError.mediaPipeUnavailable
        #endif
    }

    #if canImport(MediaPipeTasksVision)
    private func runDetectionPass(
        asset: AVURLAsset,
        track: AVAssetTrack,
        landmarker: PoseLandmarker,
        targetFPS: Double,
        profile: ExtractionProfile
    ) throws -> DetectionPassResult {
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let output: AVAssetReaderOutput
        let compositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: outputSettings)
        compositionOutput.alwaysCopiesSampleData = false
        compositionOutput.videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        if reader.canAdd(compositionOutput) {
            reader.add(compositionOutput)
            output = compositionOutput
            Self.log.debug("Pose \(profile.rawValue, privacy: .public) pass using composition output")
        } else {
            let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(trackOutput) else {
                Self.log.error("Pose \(profile.rawValue, privacy: .public) pass failed: reader cannot add output")
                throw PoseExtractionError.readerFailed
            }
            reader.add(trackOutput)
            output = trackOutput
            Self.log.debug("Pose \(profile.rawValue, privacy: .public) pass using track output fallback")
        }

        guard reader.startReading() else {
            Self.log.error("Pose \(profile.rawValue, privacy: .public) pass failed: reader did not start")
            throw PoseExtractionError.readerFailed
        }

        let sampleStep = max(1.0 / max(targetFPS, 1.0), 0.01)
        var nextSampleTime = 0.0
        var frameNumber = 0
        var sampledFrameCount = 0
        var frames: [FramePoseLandmarks] = []

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else { continue }

            if timestamp + 0.0001 < nextSampleTime {
                continue
            }
            nextSampleTime += sampleStep
            sampledFrameCount += 1

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            let timestampMs = max(Int((timestamp * 1000.0).rounded()), 0)
            let result = try landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)

            guard let poseLandmarks = result.landmarks.first, !poseLandmarks.isEmpty else {
                continue
            }

            let mapped: [PoseLandmark] = poseLandmarks.enumerated().map { idx, landmark in
                let name = idx < Self.landmarkNames.count ? Self.landmarkNames[idx] : "LANDMARK_\(idx)"
                return PoseLandmark(
                    name: name,
                    index: idx,
                    x: Float(landmark.x),
                    y: Float(landmark.y),
                    z: Float(landmark.z),
                    visibility: 1.0
                )
            }
            frames.append(
                FramePoseLandmarks(
                    frameNumber: frameNumber,
                    timestamp: timestamp,
                    landmarks: mapped
                )
            )
            frameNumber += 1
        }

        if reader.status == .failed {
            Self.log.error("Pose \(profile.rawValue, privacy: .public) pass failed during read: \(reader.error?.localizedDescription ?? "unknown", privacy: .public)")
            throw reader.error ?? PoseExtractionError.readerFailed
        }

        Self.log.debug("Pose \(profile.rawValue, privacy: .public) pass completed: sampled=\(sampledFrameCount, privacy: .public), frames=\(frames.count, privacy: .public)")
        return DetectionPassResult(frames: frames, sampledFrameCount: sampledFrameCount)
    }
    #endif
}
