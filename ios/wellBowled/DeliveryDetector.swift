import AVFoundation
import Foundation

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

/// Detects bowling deliveries in real-time from camera frames.
/// Uses MediaPipe PoseLandmarker for wrist tracking + WristVelocityTracker for spike detection.
final class DeliveryDetector: DeliveryDetecting {

    weak var delegate: DeliveryDetectionDelegate?

    // MARK: - Private State

    #if canImport(MediaPipeTasksVision)
    private var poseLandmarker: PoseLandmarker?
    #endif
    private let velocityTracker: WristVelocityTracker
    private var frameCount: Int = 0
    private var isRunning = false
    private var lastSpikeCount = 0
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
        guard !isRunning else { return }
        isRunning = true
        frameCount = 0
        velocityTracker.reset()
        lastSpikeCount = 0
        initializeLandmarker()
    }

    func stop() {
        isRunning = false
        #if canImport(MediaPipeTasksVision)
        poseLandmarker = nil
        #endif
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer, at time: CMTime) {
        guard isRunning else { return }

        // Skip frames per config (e.g., process every 2nd frame)
        frameCount += 1
        guard frameCount % WBConfig.frameSkip == 0 else { return }

        processingQueue.async { [weak self] in
            self?.detectPose(in: sampleBuffer, at: time)
        }
    }

    // MARK: - MediaPipe

    private func initializeLandmarker() {
        #if canImport(MediaPipeTasksVision)
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker", ofType: "task") else {
            print("[DeliveryDetector] pose_landmarker.task not found in bundle")
            return
        }

        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .video
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.5
            options.minTrackingConfidence = 0.5
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
            print("[DeliveryDetector] Failed to create PoseLandmarker: \(error)")
        }
        #else
        print("[DeliveryDetector] MediaPipe not available on this platform")
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

            guard let landmarks = result.landmarks.first, landmarks.count > Self.rightWrist else {
                velocityTracker.addSample(rightTheta: nil, leftTheta: nil, at: timestampSec)
                return
            }

            // Extract wrist and shoulder positions
            let rShoulder = landmarks[Self.rightShoulder]
            let rWrist = landmarks[Self.rightWrist]
            let lShoulder = landmarks[Self.leftShoulder]
            let lWrist = landmarks[Self.leftWrist]

            // Compute angles (same as Python experiment)
            let rTheta = atan2(
                Double(rWrist.x - rShoulder.x),
                Double(rWrist.y - rShoulder.y)
            )
            let lTheta = atan2(
                Double(lWrist.x - lShoulder.x),
                Double(lWrist.y - lShoulder.y)
            )

            velocityTracker.addSample(rightTheta: rTheta, leftTheta: lTheta, at: timestampSec)

            // Check if a new spike was detected
            if velocityTracker.detectedSpikes.count > lastSpikeCount {
                let spike = velocityTracker.detectedSpikes.last!
                lastSpikeCount = velocityTracker.detectedSpikes.count
                let paceBand = PaceBand.from(angularVelocity: spike.omega)

                // Capture wrist Y at spike frame (bowling arm)
                let wristY: Double? = spike.arm == .left
                    ? Double(lWrist.y)
                    : Double(rWrist.y)

                delegate?.didDetectDelivery(
                    at: spike.timestamp,
                    bowlingArm: spike.arm,
                    paceBand: paceBand,
                    wristOmega: spike.omega,
                    releaseWristY: wristY
                )
            }

        } catch {
            // Silently skip frames that fail — don't crash the pipeline
        }
        #endif
    }
}
