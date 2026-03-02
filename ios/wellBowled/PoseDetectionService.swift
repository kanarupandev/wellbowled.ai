import Foundation
import AVFoundation

// MARK: - Pose Detection Protocol

protocol PoseDetectionService {
    func detectPose(in videoURL: URL, completion: @escaping (Result<[FramePoseLandmarks], Error>) -> Void)
}

// MARK: - Frame Pose Landmarks

struct FramePoseLandmarks {
    let frameNumber: Int
    let timestamp: Double
    let landmarks: [PoseLandmark]
}
