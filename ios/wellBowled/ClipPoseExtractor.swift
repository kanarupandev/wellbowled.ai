import AVFoundation
import Foundation

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

enum PoseExtractionError: LocalizedError {
    case mediaPipeUnavailable
    case modelMissing
    case noVideoTrack
    case readerFailed

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
        }
    }
}

final class ClipPoseExtractor {

    private static let landmarkNames: [String] = [
        "NOSE", "LEFT_EYE_INNER", "LEFT_EYE", "LEFT_EYE_OUTER", "RIGHT_EYE_INNER", "RIGHT_EYE", "RIGHT_EYE_OUTER",
        "LEFT_EAR", "RIGHT_EAR", "MOUTH_LEFT", "MOUTH_RIGHT", "LEFT_SHOULDER", "RIGHT_SHOULDER",
        "LEFT_ELBOW", "RIGHT_ELBOW", "LEFT_WRIST", "RIGHT_WRIST", "LEFT_PINKY", "RIGHT_PINKY",
        "LEFT_INDEX", "RIGHT_INDEX", "LEFT_THUMB", "RIGHT_THUMB", "LEFT_HIP", "RIGHT_HIP",
        "LEFT_KNEE", "RIGHT_KNEE", "LEFT_ANKLE", "RIGHT_ANKLE", "LEFT_HEEL", "RIGHT_HEEL",
        "LEFT_FOOT_INDEX", "RIGHT_FOOT_INDEX"
    ]

    #if canImport(MediaPipeTasksVision)
    private lazy var poseLandmarker: PoseLandmarker? = {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker", ofType: "task") else {
            return nil
        }
        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .video
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.5
            options.minTrackingConfidence = 0.5
            return try PoseLandmarker(options: options)
        } catch {
            return nil
        }
    }()
    #endif

    func extractFrames(from clipURL: URL, targetFPS: Double = WBConfig.poseExtractionFPS) async throws -> [FramePoseLandmarks] {
        #if canImport(MediaPipeTasksVision)
        guard let landmarker = poseLandmarker else {
            if Bundle.main.path(forResource: "pose_landmarker", ofType: "task") == nil {
                throw PoseExtractionError.modelMissing
            }
            throw PoseExtractionError.mediaPipeUnavailable
        }

        let asset = AVURLAsset(url: clipURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw PoseExtractionError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw PoseExtractionError.readerFailed }
        reader.add(output)

        guard reader.startReading() else {
            throw PoseExtractionError.readerFailed
        }

        let sampleStep = max(1.0 / max(targetFPS, 1.0), 0.01)
        var nextSampleTime = 0.0
        var frameNumber = 0
        var frames: [FramePoseLandmarks] = []

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else { continue }

            if timestamp + 0.0001 < nextSampleTime {
                continue
            }
            nextSampleTime += sampleStep

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
            throw reader.error ?? PoseExtractionError.readerFailed
        }

        return frames
        #else
        throw PoseExtractionError.mediaPipeUnavailable
        #endif
    }
}
