import AVFoundation
import CoreGraphics
import Foundation
import os

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

private let log = Logger(subsystem: "com.wellbowled", category: "DeliveryDetector")

/// Detects bowling deliveries in real-time from camera frames.
/// Uses MediaPipe PoseLandmarker for wrist tracking + WristVelocityTracker for spike detection.
final class DeliveryDetector: DeliveryDetecting {

    weak var delegate: DeliveryDetectionDelegate?

    // MARK: - Private State

    #if canImport(MediaPipeTasksVision)
    private var poseLandmarker: PoseLandmarker?
    #endif
    private var velocityTracker: WristVelocityTracker
    private var frameCount: Int = 0
    private var isRunning = false
    private var lastSpikeCount = 0
    private var landmarkMissCount = 0
    private var poseErrorCount = 0
    private var lockedPoseCenter: CGPoint?
    private var lockMissCount = 0
    private var poseSelector = DeliveryPoseSelector()
    private let processingQueue = DispatchQueue(label: "com.wellbowled.detector")

    // Landmark indices (MediaPipe Pose)
    private static let rightShoulder = 12
    private static let rightWrist = 16
    private static let leftShoulder = 11
    private static let leftWrist = 15

    init(fps: Double = 30.0) {
        self.velocityTracker = WristVelocityTracker(fps: fps)
    }

    // MARK: - DeliveryDetecting

    func start() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunning else { return }
            self.isRunning = true
            self.frameCount = 0
            self.velocityTracker.reset()
            self.lastSpikeCount = 0
            self.landmarkMissCount = 0
            self.poseErrorCount = 0
            self.lockedPoseCenter = nil
            self.lockMissCount = 0
            self.initializeLandmarker()
            log.debug("Delivery detector started")
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            self.isRunning = false
            self.frameCount = 0
            self.velocityTracker.reset()
            self.lastSpikeCount = 0
            self.landmarkMissCount = 0
            self.poseErrorCount = 0
            self.lockedPoseCenter = nil
            self.lockMissCount = 0
            #if canImport(MediaPipeTasksVision)
            self.poseLandmarker = nil
            #endif
            log.debug("Delivery detector stopped")
        }
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer, at time: CMTime) {
        processingQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.frameCount += 1
            let frameSkip = max(WBConfig.frameSkip, 1)
            guard self.frameCount % frameSkip == 0 else { return }
            self.detectPose(in: sampleBuffer, at: time)
        }
    }

    // MARK: - MediaPipe

    private func initializeLandmarker() {
        #if canImport(MediaPipeTasksVision)
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker", ofType: "task") else {
            log.error("pose_landmarker.task not found in bundle")
            return
        }

        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .video
            options.numPoses = WBConfig.deliveryPoseMaxPoses
            options.minPoseDetectionConfidence = 0.5
            options.minTrackingConfidence = 0.5
            poseLandmarker = try PoseLandmarker(options: options)
            log.debug("MediaPipe PoseLandmarker initialized")
        } catch {
            log.error("Failed to create PoseLandmarker: \(error.localizedDescription, privacy: .public)")
        }
        #else
        log.warning("MediaPipe not available on this platform")
        #endif
    }

    private func detectPose(in sampleBuffer: CMSampleBuffer, at time: CMTime) {
        #if canImport(MediaPipeTasksVision)
        guard let landmarker = poseLandmarker,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestampMs = Int(CMTimeGetSeconds(time) * 1000)
        let timestampSec = CMTimeGetSeconds(time)

        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            let result = try landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
            let candidates = result.landmarks.compactMap { Self.makeCandidate(from: $0) }
            guard let selection = poseSelector.select(from: candidates, lockCenter: lockedPoseCenter) else {
                landmarkMissCount += 1
                lockMissCount += 1
                if lockMissCount >= WBConfig.deliveryPoseLockResetMissFrames {
                    lockedPoseCenter = nil
                }
                if self.landmarkMissCount % 60 == 0 {
                    log.debug("Pose candidates missing/invalid for \(self.landmarkMissCount) processed frames")
                }
                velocityTracker.addSample(rightTheta: nil, leftTheta: nil, at: timestampSec)
                return
            }
            landmarkMissCount = 0
            lockMissCount = 0

            let candidate = selection.candidate
            updateLockCenter(with: candidate.shoulderCenter)

            if frameCount % 90 == 0 {
                let lockDistance = selection.distanceFromLock ?? 0
                log.debug(
                    "Pose selected: candidates=\(candidates.count), shoulderSpan=\(candidate.shoulderSpan, privacy: .public), lockDistance=\(lockDistance, privacy: .public)"
                )
            }

            velocityTracker.addSample(
                rightTheta: candidate.rightTheta,
                leftTheta: candidate.leftTheta,
                at: timestampSec
            )

            // Check if a new spike was detected
            if velocityTracker.detectedSpikes.count > lastSpikeCount {
                let spike = velocityTracker.detectedSpikes.last!
                lastSpikeCount = velocityTracker.detectedSpikes.count
                guard Self.passesOverarmGate(for: spike.arm, candidate: candidate) else {
                    log.debug("Spike dropped by overarm gate: omega=\(spike.omega, privacy: .public), arm=\(spike.arm.rawValue, privacy: .public)")
                    return
                }
                let paceBand = PaceBand.from(angularVelocity: spike.omega)
                let wristY: Double = spike.arm == .left
                    ? Double(candidate.leftWrist.y)
                    : Double(candidate.rightWrist.y)

                delegate?.didDetectDelivery(
                    at: spike.timestamp,
                    bowlingArm: spike.arm,
                    paceBand: paceBand,
                    wristOmega: spike.omega,
                    releaseWristY: wristY
                )
                log.debug(
                    "Delivery detected: ts=\(spike.timestamp, privacy: .public), arm=\(spike.arm.rawValue, privacy: .public), omega=\(spike.omega, privacy: .public)"
                )
            }

        } catch {
            poseErrorCount += 1
            if poseErrorCount % 30 == 0 {
                log.warning(
                    "Pose detection errors observed: count=\(self.poseErrorCount), latest=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        #endif
    }

    private func updateLockCenter(with center: CGPoint) {
        guard let previous = lockedPoseCenter else {
            lockedPoseCenter = center
            return
        }

        let alpha = min(max(WBConfig.deliveryPoseLockSmoothing, 0), 1)
        lockedPoseCenter = CGPoint(
            x: previous.x + (center.x - previous.x) * alpha,
            y: previous.y + (center.y - previous.y) * alpha
        )
    }

    private static func passesOverarmGate(for arm: BowlingArm, candidate: DeliveryPoseCandidate) -> Bool {
        let margin = WBConfig.deliveryOverarmWristAboveShoulderMargin
        switch arm {
        case .left:
            return Double(candidate.leftWrist.y) <= Double(candidate.leftShoulder.y) + margin
        case .right:
            return Double(candidate.rightWrist.y) <= Double(candidate.rightShoulder.y) + margin
        case .unknown:
            return false
        }
    }

    #if canImport(MediaPipeTasksVision)
    private static func makeCandidate(from landmarks: [NormalizedLandmark]) -> DeliveryPoseCandidate? {
        guard landmarks.count > Self.rightWrist else { return nil }

        let rShoulder = landmarks[Self.rightShoulder]
        let rWrist = landmarks[Self.rightWrist]
        let lShoulder = landmarks[Self.leftShoulder]
        let lWrist = landmarks[Self.leftWrist]

        let points = [rShoulder, rWrist, lShoulder, lWrist]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        return DeliveryPoseCandidate(
            rightShoulder: CGPoint(x: Double(rShoulder.x), y: Double(rShoulder.y)),
            rightWrist: CGPoint(x: Double(rWrist.x), y: Double(rWrist.y)),
            leftShoulder: CGPoint(x: Double(lShoulder.x), y: Double(lShoulder.y)),
            leftWrist: CGPoint(x: Double(lWrist.x), y: Double(lWrist.y))
        )
    }
    #endif
}
