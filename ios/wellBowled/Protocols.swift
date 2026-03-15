import AVFoundation
import Foundation

// MARK: - Delivery Detection

/// Receives camera frames and detects bowling deliveries in real-time.
/// Implementations: MediaPipe wrist velocity spike, or future ML models.
protocol DeliveryDetecting: AnyObject {
    var delegate: DeliveryDetectionDelegate? { get set }
    func start()
    func stop()
    func processFrame(_ sampleBuffer: CMSampleBuffer, at time: CMTime)
}

protocol DeliveryDetectionDelegate: AnyObject {
    func didDetectDelivery(
        at timestamp: Double,
        bowlingArm: BowlingArm,
        paceBand: PaceBand,
        wristOmega: Double,
        releaseWristY: Double?
    )
}

// MARK: - Speech Announcement

/// Speaks delivery count, pace, and challenge targets aloud.
/// The app announces deterministic info (count, pace) instantly via TTS.
/// Extensible: future implementations could use Live API voice directly.
protocol SpeechAnnouncing: AnyObject {
    var isSpeaking: Bool { get }
    func announceDelivery(count: Int, pace: PaceBand)
    func announceChallenge(target: String)
    func announceChallengeResult(_ text: String)
    func speak(_ text: String)
    func stop()
}

// MARK: - Voice Mate

/// Bidirectional voice conversation with the expert mate.
/// Current: Gemini Live API (responds to user speech).
/// Future: could become proactive (pilot run assessment, environment check,
/// session control, adaptive coaching targets).
protocol VoiceMateService: AnyObject {
    var delegate: VoiceMateDelegate? { get set }
    var isConnected: Bool { get }
    var isSpeaking: Bool { get }

    func connect() async throws
    func disconnect() async

    /// Send a video frame for visual context (the mate "sees" the session)
    func sendVideoFrame(_ jpegData: Data)

    /// Send microphone audio (the mate "hears" the bowler)
    func sendAudio(_ pcmData: Data)

    /// Send text context (e.g., delivery detected, challenge target set)
    /// This enriches the mate's understanding without requiring speech.
    func sendContext(_ text: String) async

    /// Ask the mate to announce a challenge target.
    /// Fallback behavior (e.g. local TTS) is managed by SessionViewModel.
    func speakChallenge(target: String) async
}

protocol VoiceMateDelegate: AnyObject {
    /// Mate is speaking — play this audio
    func voiceMate(didReceiveAudio pcmData: Data)

    /// Mate's speech was transcribed
    func voiceMate(didTranscribe text: String)

    /// Bowler speech transcribed from input audio.
    func voiceMate(didTranscribeUser text: String)

    /// Mate finished a conversational turn
    func voiceMateDidFinishTurn()

    /// Connection state changed
    func voiceMate(didChangeConnectionState connected: Bool)

    /// WebSocket closed unexpectedly with reason (for diagnostics)
    func voiceMate(didDisconnect reason: String)

    /// Model requested session end via tool call.
    @MainActor
    func voiceMate(didRequestEndSession reason: String) async
}

extension VoiceMateDelegate {
    func voiceMate(didTranscribeUser text: String) {}
    @MainActor
    func voiceMate(didRequestEndSession reason: String) async {}
}

// MARK: - Clip Extraction

/// Extracts short clips from a recording around a timestamp.
protocol ClipExtracting: AnyObject {
    func extractClip(
        from recordingURL: URL,
        at timestamp: Double,
        preRoll: Double,
        postRoll: Double
    ) async throws -> URL
}

// MARK: - Delivery Analysis

/// Analyzes a delivery clip using Gemini generateContent.
/// Separate from VoiceMate — this is async, post-hoc analysis.
protocol DeliveryAnalyzing: AnyObject {
    func analyzeDelivery(clipURL: URL) async throws -> DeliveryAnalysis
    func evaluateChallenge(clipURL: URL, target: String) async throws -> ChallengeResult
    func generateSessionSummary(deliveries: [Delivery]) async throws -> SessionSummary
}

// MARK: - Camera

/// Camera capture with multiple output streams.
protocol CameraProviding: AnyObject {
    var isRecording: Bool { get }
    var currentRecordingURL: URL? { get }
    var previewLayer: AVCaptureVideoPreviewLayer { get }

    /// Called for each video frame (for MediaPipe + Live API)
    var onVideoFrame: ((CMSampleBuffer, CMTime) -> Void)? { get set }

    /// Called for each audio sample (for Live API mic input)
    var onAudioSample: ((CMSampleBuffer) -> Void)? { get set }

    func startSession() async
    func stopSession()
    func startRecording() throws
    func stopRecording()
}

// MARK: - Speed Estimation

/// Estimates ball speed from a delivery clip using calibrated stump positions.
protocol SpeedEstimating {
    func estimateSpeed(
        clipURL: URL,
        calibration: StumpCalibration,
        deliveryTimestamp: Double
    ) async throws -> SpeedEstimate
}
