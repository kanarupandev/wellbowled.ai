import AVFoundation
import Combine
import os
import Photos
import SwiftUI
import UIKit

private let log = Logger(subsystem: "com.wellbowled", category: "SessionVM")

/// Full session ViewModel: Live API voice + MediaPipe detection + TTS + recording + analysis.
/// Pipeline: Camera → (MediaPipe detection + Live API voice) → TTS count → clip extraction → Gemini analysis
@MainActor
final class SessionViewModel: ObservableObject {

    private enum LiveFlowPhase {
        case starting
        case active
    }

    /// Tracks the mate's conversational phase across the full session lifecycle.
    /// The voice connection persists beyond bowling — the mate walks through results.
    enum MatePhase: Equatable {
        case idle                       // Not connected
        case liveBowling                // Active session — live expert analysis
        case postSessionReview          // Session ended — walking through analysis results
    }

    enum SessionVideoSaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    // MARK: - Published State

    @Published var connectionState: LiveConnectionState = .disconnected
    @Published var lastTranscript: String = ""
    @Published var isMateSpeaking: Bool = false
    @Published var errorMessage: String?
    @Published var debugLog: String = ""
    @Published var livePreviewImage: UIImage?

    // Session state
    @Published var session = Session()
    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0
    @Published var sessionRemainingSeconds: TimeInterval = WBConfig.liveSessionDefaultDurationSeconds
    private var sessionDurationSeconds: TimeInterval = WBConfig.liveSessionDefaultDurationSeconds
    @Published var currentChallengeTarget: String?
    @Published var isPreparingClips: Bool = false
    @Published var clipPreparationProgress: Double = 0
    @Published private(set) var clipPreparationStatusMessage: String = ""
    @Published private(set) var deepAnalysisStatusByDelivery: [UUID: DeliveryDeepAnalysisStatus] = [:]
    @Published private(set) var deepAnalysisArtifactsByDelivery: [UUID: DeliveryDeepAnalysisArtifacts] = [:]
    @Published private(set) var lastSessionRecordingURL: URL?
    @Published private(set) var sessionVideoSaveStatus: SessionVideoSaveStatus = .idle
    @Published private(set) var compositedExportStatus: SessionVideoSaveStatus = .idle
    @Published private(set) var cameraFlipDisabled: Bool = false

    // Persistent voice mate state
    @Published private(set) var matePhase: MatePhase = .idle
    @Published var reviewDeliveryIndex: Int = 0

    // Stump calibration state (published for CalibrationOverlayView)
    @Published private(set) var calibrationState: StumpDetectionService.CalibrationState = .idle

    // Stump marking + monitoring
    @Published var sessionInstruction: String?
    @Published var isMarkingStumps: Bool = false
    @Published var showSpeedSetup: Bool = false
    @Published var speedDistanceMetres: Double = 18.9
    @Published private(set) var cliffState: CliffDetector.State = .monitoring
    @Published private(set) var stumpMonitoringActive: Bool = false

    // Agent playback commands (review agent controls video replay)
    struct PlaybackCommand: Equatable {
        let id = UUID()
        let action: PlaybackAction
        let timestamp: Double?
        let rate: Float?

        static func == (lhs: PlaybackCommand, rhs: PlaybackCommand) -> Bool {
            lhs.id == rhs.id
        }
    }

    enum PlaybackAction: String {
        case play
        case pause
        case slowMo
        case seek
        case focusPhase
    }

    @Published var playbackCommand: PlaybackCommand?

    // MARK: - Services

    let cameraService = CameraService()
    private let liveService = GeminiLiveService()
    private let stumpDetectionService = StumpDetectionService()
    private let audioManager = AudioSessionManager.shared
    private let detector = DeliveryDetector(fps: 30.0)
    private let tts = TTSService()
    private let clipExtractor = ClipExtractor()
    private let analysisService = GeminiAnalysisService()
    private let clipPoseExtractor = ClipPoseExtractor()
    private let speedEstimationService = SpeedEstimationService()
    private let cliffDetector = CliffDetector(fps: Double(WBConfig.speedCalibrationFPS))
    // nonisolated(unsafe) because these are accessed from the video callback thread.
    // Thread safety: only written from one thread at a time (camera callback is serial).
    nonisolated(unsafe) private var cliffFrameCounter: Int = 0
    nonisolated(unsafe) private var cliffPrevGray: [UInt8]?
    nonisolated(unsafe) private var cliffROI: CGRect?
    private var cliffTimestamps: [Double] = []

    private var cancellables = Set<AnyCancellable>()
    private let ciContext = CIContext()  // Reuse — creating per frame is expensive
    private let recordingOffsetStore = RecordingOffsetStore()
    private var sessionTimerTask: Task<Void, Never>?
    private var isEndingSession = false
    private var challengeEngine = ChallengeEngine(targets: WBConfig.challengeTargets, shuffle: true)
    private var challengeTargetBySequence: [Int: String] = [:]
    private var shouldSendProactiveGreeting = false
    private var didSendProactiveGreeting = false
    private var flowPhase: LiveFlowPhase = .starting
    private var sessionStartTime: Date?
    private var clipPreparationTask: Task<Void, Never>?
    private var deepAnalysisTasksByDelivery: [UUID: Task<Void, Never>] = [:]
    private var telemetryTasksByDelivery: [UUID: Task<Void, Never>] = [:]
    private var challengeEvaluatedDeliveries = Set<UUID>()
    private var liveAudioChunkCounter = 0
    private var liveMicChunkCounter = 0
    private var useCameraAudioFallback = false
    private var reconnectAttempts = 0

    // Live segment detection queues
    private var reviewAgentTimeoutTask: Task<Void, Never>?
    private var liveSegmentTimerTask: Task<Void, Never>?
    private var liveDetectionQueue: [(url: URL, startTime: Double)] = []
    private var liveDeepAnalysisQueue: [UUID] = []
    private var liveDetectionTask: Task<Void, Never>?
    private var liveDeepAnalysisTask: Task<Void, Never>?
    private var liveScannedUpTo: Double = 0
    private var liveDetectedTimestamps: [Double] = []

    // MARK: - Init

    init() {
        liveService.delegate = self
        detector.delegate = self

        liveService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.connectionState = newState
                if case .connected = newState {
                    Task { @MainActor in
                        await self.maybeSendProactiveGreetingIfNeeded()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Lifecycle

    func startSession() async {
        guard !session.isActive else {
            log.debug("startSession ignored: session already active")
            return
        }

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                rollbackSessionStartFailure(reason: "Camera access denied. Enable camera permission in Settings.")
                return
            }
        } else if cameraStatus != .authorized {
            rollbackSessionStartFailure(reason: "Camera unavailable. Enable camera permission in Settings.")
            return
        }

        log.debug("Starting session...")
        errorMessage = nil
        session.start(mode: .freePlay)
        calibrationState = .idle
        cameraService.setSpeedMode(false)
        cameraFlipDisabled = false
        challengeTargetBySequence = [:]
        challengeEngine.reset(shuffle: true)
        session.currentChallenge = nil
        currentChallengeTarget = nil
        shouldSendProactiveGreeting = true
        didSendProactiveGreeting = false
        flowPhase = .starting
        sessionStartTime = nil
        sessionDurationSeconds = WBConfig.liveSessionDefaultDurationSeconds
        sessionRemainingSeconds = sessionDurationSeconds
        lastSessionRecordingURL = nil
        sessionVideoSaveStatus = .idle
        livePreviewImage = nil
        clipPreparationTask?.cancel()
        clipPreparationTask = nil
        isPreparingClips = false
        clipPreparationProgress = 0
        clipPreparationStatusMessage = ""
        isAnalyzing = false
        analysisProgress = 0
        cancelAllDeepAnalysisTasks(resetState: true)
        challengeEvaluatedDeliveries = []
        liveAudioChunkCounter = 0
        liveMicChunkCounter = 0
        useCameraAudioFallback = false
        reconnectAttempts = 0
        startSessionTimer()

        // 1. Configure audio session (only for live mate)
        if WBConfig.enableLiveAPI {
            do {
                audioManager.stopPlaybackEngine()
                try audioManager.configure()
                try audioManager.startPlaybackEngine()
                let liveService = self.liveService
                useCameraAudioFallback = !audioManager.startLiveInputCapture { pcmData in
                    liveService.sendAudio(pcmData)
                }
                log.debug("Audio configured for live mate")
            } catch {
                log.warning("Audio setup failed (continuing without live mate): \(error.localizedDescription)")
            }
        }

        // 2. Start camera
        await cameraService.startSession()
        log.debug("Camera started")

        // 3. Start recording (for post-session clip extraction)
        cameraService.resetRecordingSegments()
        do {
            try cameraService.startRecording()
            log.debug("Recording started")
        } catch {
            log.debug("Recording start failed (session continues without clip extraction): \(error.localizedDescription, privacy: .public)")
        }

        // 3b. Start live segment detection (only with live API)
        if WBConfig.enableLiveAPI {
            startLiveSegmentDetection()
        }

        // 4. Wire camera outputs
        wireCameraOutputs()
        log.debug("Camera outputs wired")

        // 6. Connect to Gemini Live API (only if enabled)
        if WBConfig.enableLiveAPI {
            do {
                debugLog += "Connecting...\n"
                try await liveService.connect()
                debugLog += "Connected!\n"
                matePhase = .liveBowling
                await maybeSendProactiveGreetingIfNeeded()
            } catch {
                debugLog += "FAIL: \(error.localizedDescription)\n"
                errorMessage = "Connection failed: \(error.localizedDescription)"
            }
        }

        // 7. Session is now active — short instruction (voiced + subtitled)
        sessionInstruction = "Point camera at stumps, tap Mark Stumps"
        tts.speak("Point your camera at the stumps and tap Mark Stumps")
    }

    func endSession() async {
        guard session.isActive || isEndingSession else { return }
        if isEndingSession { return }
        isEndingSession = true
        defer { isEndingSession = false }

        log.debug("Ending session...")
        sessionTimerTask?.cancel()
        sessionTimerTask = nil

        // Save fallback recording URL before stopping.
        let fallbackRecordingURL = cameraService.currentRecordingURL
        sessionVideoSaveStatus = .idle

        // Unwire camera
        cameraService.onVideoFrame = nil
        cameraService.onAudioSample = nil

        tts.stop()
        stopCliffDetection()
        stopLiveSegmentDetection()

        // Stop recording + camera (but keep audio alive for voice mate)
        cameraService.stopRecording()
        cameraService.stopSession()

        // End session BEFORE connecting review agent — but review agent uses matePhase
        // which is checked independently from session.isActive for auto-reconnect.
        session.end()

        // Connect a FRESH review agent — dedicated to walking through analysis results.
        // Must be AFTER session.end() but AWAITED so matePhase is set before we continue.
        if liveService.isConnected || WBConfig.enableLiveAPI {
            await connectReviewAgent()
        } else {
            matePhase = .idle
        }
        sessionRemainingSeconds = 0
        UIApplication.shared.isIdleTimerDisabled = true
        lastTranscript = ""
        isMateSpeaking = false
        errorMessage = nil
        shouldSendProactiveGreeting = false
        didSendProactiveGreeting = false
        flowPhase = .starting
        sessionStartTime = nil
        livePreviewImage = nil
        log.debug("Session ended. Deliveries: \(self.session.deliveryCount)")

        // Post-session: clip preparation only (deep analysis is on-demand per delivery).
        clipPreparationStatusMessage = "Preparing session replay..."
        let recordingURL = await resolveRecordingURLForPostSession(fallback: fallbackRecordingURL)
        lastSessionRecordingURL = recordingURL
        if let url = recordingURL {
            startClipPreparation(recordingURL: url)
        } else {
            isPreparingClips = false
            clipPreparationProgress = 0
            clipPreparationStatusMessage = "Session recording unavailable."
            log.warning("Post-session clip prep skipped: recording URL unavailable")
        }
    }

    /// Reuses the same post-session detection/clip pipeline for a user-picked recording.
    func prepareImportedSessionReplay(recordingURL: URL, mode: SessionMode = .freePlay) async {
        log.debug("Preparing imported session replay: file=\(recordingURL.lastPathComponent, privacy: .public), mode=\(mode.rawValue, privacy: .public)")

        sessionTimerTask?.cancel()
        sessionTimerTask = nil
        clipPreparationTask?.cancel()
        clipPreparationTask = nil
        cancelAllDeepAnalysisTasks(resetState: true)
        stopLiveSegmentDetection()

        cameraService.onVideoFrame = nil
        cameraService.onAudioSample = nil
        tts.stop()
        await disconnectMate()
        cameraService.stopRecording()
        cameraService.stopSession()

        session.start(mode: mode)
        session.end()
        session.deliveries.removeAll()
        session.summary = nil

        challengeTargetBySequence = [:]
        currentChallengeTarget = nil
        challengeEngine.reset(shuffle: true)
        challengeEvaluatedDeliveries = []
        shouldSendProactiveGreeting = false
        didSendProactiveGreeting = false
        flowPhase = .starting
        sessionStartTime = nil
        liveAudioChunkCounter = 0
        liveMicChunkCounter = 0
        useCameraAudioFallback = false

        errorMessage = nil
        lastTranscript = ""
        isMateSpeaking = false
        sessionRemainingSeconds = 0
        isAnalyzing = false
        analysisProgress = 0
        isPreparingClips = false
        clipPreparationProgress = 0
        clipPreparationStatusMessage = "Preparing clip for analysis..."
        livePreviewImage = nil
        cameraFlipDisabled = false
        sessionVideoSaveStatus = .idle
        recordingOffsetStore.reset()

        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            lastSessionRecordingURL = nil
            clipPreparationStatusMessage = "Uploaded recording is unavailable."
            log.error("Imported replay failed: recording missing at path=\(recordingURL.path, privacy: .public)")
            return
        }

        lastSessionRecordingURL = recordingURL

        // Validate clip size and duration limits
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as? Int ?? 0
            if fileSize > WBConfig.clipMaxSizeBytes {
                clipPreparationStatusMessage = "Clip too large (\(fileSize / 1024 / 1024)MB). Max \(WBConfig.clipMaxSizeBytes / 1024 / 1024)MB."
                log.warning("Imported clip rejected: \(fileSize) bytes > \(WBConfig.clipMaxSizeBytes)")
                return
            }
        } catch {
            log.warning("Could not check file size: \(error.localizedDescription)")
        }

        let asset = AVURLAsset(url: recordingURL)
        let durationTime = (try? await asset.load(.duration)) ?? .zero
        let durationSecs = CMTimeGetSeconds(durationTime)

        if durationSecs > WBConfig.clipMaxDurationSeconds {
            clipPreparationStatusMessage = "Clip too long (\(String(format: "%.0f", durationSecs))s). Max \(String(format: "%.0f", WBConfig.clipMaxDurationSeconds))s."
            log.warning("Imported clip rejected: \(durationSecs)s > \(WBConfig.clipMaxDurationSeconds)s")
            return
        }

        // Short clip → treat as single delivery, skip segment scanning entirely
        log.info("Imported clip accepted: \(String(format: "%.1f", durationSecs))s — treating as single delivery")
        clipPreparationStatusMessage = "Generating thumbnail..."
        clipPreparationProgress = 0.3

        // Generate thumbnail from midpoint
        let thumbnail = ClipThumbnailGenerator.releaseThumbnail(
            from: recordingURL,
            releaseOffset: durationSecs / 2.0
        )

        // Create a single delivery with the clip already attached
        let delivery = Delivery(
            timestamp: 0,
            releaseTimestamp: durationSecs / 2.0,
            status: .queued,
            videoURL: recordingURL,
            thumbnail: thumbnail,
            sequence: 1
        )
        session.addDelivery(delivery)
        clipPreparationProgress = 0.6
        clipPreparationStatusMessage = "Analyzing delivery..."

        refreshSessionSummary()
        isPreparingClips = false
        clipPreparationProgress = 1.0

        // Auto-trigger deep analysis on the single delivery
        log.info("Auto-triggering deep analysis for imported clip")
        await runDeepAnalysisIfNeeded(for: delivery.id)
    }

    /// Fully disconnect the voice mate. Called when the user exits to home.
    /// This tears down the Live API WebSocket and audio session.
    func disconnectMate() async {
        log.debug("Disconnecting mate (full teardown)")
        reviewAgentTimeoutTask?.cancel()
        reviewAgentTimeoutTask = nil
        await liveService.disconnect()
        audioManager.stopLiveInputCapture()
        audioManager.stopPlaybackEngine()
        audioManager.deactivateSession()
        matePhase = .idle
        lastTranscript = ""
        isMateSpeaking = false
        reconnectAttempts = 0
    }

    /// Navigate to a specific delivery in review mode and tell the mate.
    func reviewDelivery(at index: Int) async {
        guard matePhase == .postSessionReview else { return }
        guard index >= 0, index < session.deliveryCount else { return }
        reviewDeliveryIndex = index
        let delivery = session.deliveries[index]
        let seq = index + 1

        var parts: [String] = ["[REVIEWING DELIVERY \(seq)] The bowler jumped to delivery \(seq). Talk them through it."]
        if let kph = delivery.speedKph, let margin = delivery.speedErrorMarginKph {
            parts.append("Estimated speed: \(String(format: "%.0f", kph)) ±\(String(format: "%.0f", margin)) kph (video-based, not radar).")
        } else if let kph = delivery.speedKph {
            parts.append("Estimated speed: ~\(String(format: "%.0f", kph)) kph (video-based, not radar).")
        }
        if let report = delivery.report, !report.isEmpty {
            parts.append("Report: \(report)")
        }
        if let phases = delivery.phases, !phases.isEmpty {
            for phase in phases {
                var desc = "\(phase.name) [\(phase.status)]: \(phase.observation)"
                if let ts = phase.clipTimestamp {
                    desc += " @ \(String(format: "%.1f", ts))s"
                }
                if !phase.tip.isEmpty { desc += " — Drill: \(phase.tip)" }
                parts.append(desc)
            }
        }
        if let matches = delivery.dnaMatches, let top = matches.first {
            parts.append("DNA: \(top.bowlerName) (\(top.country)) \(Int(top.similarityPercent))%. Closest: \(top.closestPhase). Diverges: \(top.biggestDifference).")
        }
        if let target = challengeTargetBySequence[seq] {
            parts.append("Challenge target was: \(target).")
        }

        if liveService.isConnected {
            await liveService.sendContext(parts.joined(separator: " "))
        }
    }

    func cancelReplayPreparation() {
        log.debug("Cancel replay preparation requested")
        clipPreparationTask?.cancel()
        clipPreparationTask = nil
        isPreparingClips = false
        cancelAllDeepAnalysisTasks(resetState: false)
    }

    private func resolveRecordingURLForPostSession(fallback: URL?) async -> URL? {
        // When camera was flipped, the last segment needs extra time to finalize.
        // Poll until it appears (up to 3s) instead of a fixed 0.5s wait.
        if cameraFlipDisabled {
            for attempt in 1...6 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s per attempt
                let urls = cameraService.recordedSegmentURLs
                let segs = RecordingSegmentPlanner.existingSegments(urls) { FileManager.default.fileExists(atPath: $0.path) }
                log.debug("Camera flip wait attempt \(attempt): \(segs.count) segments found")
                if segs.count > 1, let lastSeg = segs.last {
                    log.info("Camera was flipped; using last segment: \(lastSeg.lastPathComponent, privacy: .public)")
                    return lastSeg
                }
            }
            // Fallback: use the currentRecordingURL (front camera file path, may still be finalizing)
            if let fb = fallback, FileManager.default.fileExists(atPath: fb.path) {
                log.warning("Camera flip: second segment not found; falling back to \(fb.lastPathComponent, privacy: .public)")
                return fb
            }
        }

        // Normal path (no flip): short wait then resolve.
        let waitNanos = UInt64(max(0, WBConfig.recordingSegmentFinalizeDelaySeconds) * 1_000_000_000)
        if waitNanos > 0 {
            try? await Task.sleep(nanoseconds: waitNanos)
        }

        let segments = RecordingSegmentPlanner.existingSegments(
            cameraService.recordedSegmentURLs
        ) { url in
            FileManager.default.fileExists(atPath: url.path)
        }

        if segments.count <= 1 {
            return segments.first ?? fallback
        }

        clipPreparationStatusMessage = "Merging camera-switch recording segments..."
        if let merged = await mergeRecordingSegments(segments) {
            log.info("Merged \(segments.count) recording segments into \(merged.lastPathComponent, privacy: .public)")
            return merged
        }

        log.warning("Recording segment merge failed; using last segment")
        return RecordingSegmentPlanner.resolvedRecordingURL(
            mergedURL: nil,
            segments: segments,
            fallback: fallback
        )
    }

    private func mergeRecordingSegments(_ segmentURLs: [URL]) async -> URL? {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for segmentURL in segmentURLs {
            let asset = AVURLAsset(url: segmentURL)
            guard let sourceVideoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            let duration = (try? await asset.load(.duration)) ?? .zero
            if duration <= .zero { continue }

            let timeRange = CMTimeRange(start: .zero, duration: duration)
            do {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)
                if let sourceAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                    try audioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: cursor)
                }
                cursor = CMTimeAdd(cursor, duration)
            } catch {
                log.warning("Failed to append segment \(segmentURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard cursor > .zero else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merged-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        if exporter.status == .completed && FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        if let error = exporter.error {
            log.warning("Segment merge export failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func rollbackSessionStartFailure(reason: String) {
        log.error("\(reason, privacy: .public)")
        sessionTimerTask?.cancel()
        sessionTimerTask = nil
        clipPreparationTask?.cancel()
        clipPreparationTask = nil
        cancelAllDeepAnalysisTasks(resetState: true)
        stopLiveSegmentDetection()

        cameraService.onVideoFrame = nil
        cameraService.onAudioSample = nil
        tts.stop()
        audioManager.stopPlaybackEngine()
        audioManager.stopLiveInputCapture()
        cameraService.stopRecording()
        cameraService.stopSession()

        session.end()
        session.deliveries.removeAll()
        sessionDurationSeconds = WBConfig.liveSessionDefaultDurationSeconds
        sessionRemainingSeconds = sessionDurationSeconds
        isPreparingClips = false
        clipPreparationProgress = 0
        clipPreparationStatusMessage = ""
        isAnalyzing = false
        analysisProgress = 0
        shouldSendProactiveGreeting = false
        didSendProactiveGreeting = false
        flowPhase = .starting
        sessionStartTime = nil
        lastSessionRecordingURL = nil
        sessionVideoSaveStatus = .idle
        livePreviewImage = nil
        errorMessage = reason
    }

    // MARK: - Session Video Export

    func saveLastSessionVideoToPhotos() async {
        guard sessionVideoSaveStatus != .saving else { return }

        guard let videoURL = lastSessionRecordingURL else {
            sessionVideoSaveStatus = .failed("No session recording available to save.")
            return
        }

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            sessionVideoSaveStatus = .failed("Session recording file is unavailable.")
            return
        }

        sessionVideoSaveStatus = .saving

        let auth = await ensurePhotoLibraryAddPermission()
        guard auth else {
            sessionVideoSaveStatus = .failed("Photo Library access denied. Allow access in Settings.")
            return
        }

        do {
            try await persistVideoToPhotoLibrary(videoURL)
            sessionVideoSaveStatus = .saved
            log.debug("Saved session recording to Photos: \(videoURL.lastPathComponent, privacy: .public)")
        } catch {
            sessionVideoSaveStatus = .failed("Save failed: \(error.localizedDescription)")
            log.error("Failed saving session recording to Photos: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensurePhotoLibraryAddPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return requested == .authorized || requested == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func persistVideoToPhotoLibrary(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    let nsError = error ?? NSError(
                        domain: "com.wellbowled.photos",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not save video to Photos."]
                    )
                    continuation.resume(throwing: nsError)
                }
            }
        }
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        let startedAt = session.startedAt ?? Date()
        sessionStartTime = startedAt

        sessionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let elapsed = Date().timeIntervalSince(startedAt)
                let duration = self.sessionDurationSeconds
                let remaining = max(duration - elapsed, 0)
                self.sessionRemainingSeconds = remaining

                if remaining <= 0 {
                    let minutes = Int((duration / 60).rounded())
                    self.errorMessage = "\(minutes)-minute live session complete."
                    await self.endSession()
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    var sessionRemainingText: String {
        let total = max(Int(sessionRemainingSeconds.rounded(.down)), 0)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Camera Wiring

    func toggleCamera() {
        guard !cameraFlipDisabled else { return }
        cameraService.toggleCamera { [weak self] newPosition in
            guard let self else { return }
            Task { @MainActor in
                self.cameraFlipDisabled = true
                await self.handleCameraSwitched(to: newPosition)
            }
        }
    }

    private func handleCameraSwitched(to position: AVCaptureDevice.Position) async {
        // Reset recording offset so post-flip deliveries map correctly to the new segment.
        recordingOffsetStore.reset()
        // Clear pre-flip deliveries — only the post-flip segment will be analyzed.
        session.deliveries.removeAll()
        log.info("Camera flipped to \(position == .front ? "front" : "back"); offset reset, pre-flip deliveries cleared")

        guard session.isActive, liveService.isConnected else { return }
        await liveService.sendContext(Self.cameraSwitchContext(for: position))
    }

    private func wireCameraOutputs() {
        // Capture first frame timestamp so delivery timestamps can be offset to recording-relative.
        recordingOffsetStore.reset()
        let minFrameInterval = 1.0 / WBConfig.liveAPIFrameRate
        var lastEncodedFrameTime: CFAbsoluteTime = 0

        // Video frames → Live API + cliff detection
        let ciCtx = self.ciContext  // capture to avoid accessing MainActor self from bg
        cameraService.onVideoFrame = { [weak self] sampleBuffer, timestamp in
            guard let self else { return }

            // Track recording start time for clip extraction offset
            self.recordingOffsetStore.markIfNeeded(timestamp)

            // Cliff detection: process every 8th frame for stump ROI energy (~15μs per frame)
            if let roi = self.cliffROI {
                self.cliffFrameCounter += 1
                if self.cliffFrameCounter % 8 == 0 {
                    self.processCliffFrame(sampleBuffer, roi: roi)
                }
            }

            // Feed Live API at configured rate only; avoid expensive frame encoding on every camera frame.
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastEncodedFrameTime >= minFrameInterval else { return }
            lastEncodedFrameTime = now

            // Encode frame for Live API — reuse CIContext (creating per frame is expensive).
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImageOrientation: UIImage.Orientation = {
                let cameraPosition = self.cameraService.cameraPosition
                if WBConfig.forcePortraitCameraOrientation {
                    return cameraPosition == .front ? .leftMirrored : .right
                }
                return .up
            }()
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: uiImageOrientation)
            guard let jpegData = uiImage.jpegData(compressionQuality: CGFloat(WBConfig.liveAPIJPEGQuality) / 100.0) else { return }
            self.liveService.sendVideoFrame(jpegData)
        }

        // Audio samples → Live API
        cameraService.onAudioSample = { [weak self] sampleBuffer in
            guard let self else { return }
            guard self.useCameraAudioFallback else { return }
            guard let pcmData = AudioSessionManager.resampleToLiveAPI(sampleBuffer) else { return }
            self.liveMicChunkCounter += 1
            if self.liveMicChunkCounter == 1 || self.liveMicChunkCounter % 100 == 0 {
                log.debug("Fallback camera mic chunk count=\(self.liveMicChunkCounter) bytes=\(pcmData.count)")
            }
            self.liveService.sendAudio(pcmData)
        }
    }

    // MARK: - Post-Session Preparation (Immediate)

    private func startClipPreparation(recordingURL: URL) {
        clipPreparationTask?.cancel()
        let sourceSessionStart = session.startedAt
        clipPreparationStatusMessage = "Scanning recording for deliveries..."
        log.debug("Starting clip preparation task for recording: \(recordingURL.lastPathComponent, privacy: .public)")
        clipPreparationTask = Task { [weak self] in
            await self?.prepareDeliveryClips(
                recordingURL: recordingURL,
                sourceSessionStart: sourceSessionStart
            )
        }
    }

    private func prepareDeliveryClips(recordingURL: URL, sourceSessionStart: Date?) async {
        guard !Task.isCancelled else { return }

        isPreparingClips = true
        clipPreparationProgress = 0
        clipPreparationStatusMessage = "Finalizing session replay..."

        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            clipPreparationStatusMessage = "Session recording unavailable."
            isPreparingClips = false
            log.error("Clip preparation aborted: recording file missing at path=\(recordingURL.path, privacy: .public)")
            return
        }

        let recordingOffset = recordingOffsetStore.startSeconds()
        log.debug("Clip prep: recordingOffset=\(recordingOffset), file=\(recordingURL.lastPathComponent, privacy: .public)")
        log.debug("Clip prep: \(self.session.deliveries.count) deliveries, timestamps=\(self.session.deliveries.map { String(format: "%.2f", $0.timestamp) })")
        let recordingAsset = AVURLAsset(url: recordingURL)
        let recordingDurationTime = (try? await recordingAsset.load(.duration)) ?? .zero
        let recordingDuration = max(CMTimeGetSeconds(recordingDurationTime), 0)

        // No segment-based Gemini scanning — deliveries are detected on-device during the session.
        // Post-session just clips already-detected deliveries.
        clipPreparationProgress = 0.5
        log.info("Post-session clip prep: \(self.session.deliveryCount) deliveries to clip (on-device detected)")

        guard !session.deliveries.isEmpty else {
            clipPreparationProgress = 1
            clipPreparationStatusMessage = "No deliveries found after recording scan."
            isPreparingClips = false
            refreshSessionSummary()
            log.info("Clip preparation completed: no deliveries found in live + batch detection paths")
            return
        }

        let preRoll = WBConfig.clipPreRoll
        let postRoll = WBConfig.clipPostRoll
        clipPreparationStatusMessage = "Clipping \(session.deliveries.count) detected deliveries..."
        log.debug("Clip preparation started: deliveries=\(self.session.deliveries.count), preRoll=\(preRoll, privacy: .public), postRoll=\(postRoll, privacy: .public)")
        for index in session.deliveries.indices {
            session.deliveries[index].status = .clipping
            session.deliveries[index].videoURL = nil
            session.deliveries[index].thumbnail = nil
        }
        let total = Double(max(session.deliveries.count, 1))
        let clipCounter = ActorCounter()

        await withTaskGroup(of: (Int, URL?, Error?).self) { group in
            for (index, delivery) in self.session.deliveries.enumerated() {
                group.addTask { [clipExtractor] in
                    let clipTimestamp = max(delivery.timestamp - recordingOffset, 0)
                    do {
                        let clipURL = try await clipExtractor.extractClip(
                            from: recordingURL,
                            at: clipTimestamp,
                            preRoll: preRoll,
                            postRoll: postRoll
                        )
                        return (index, clipURL, nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }

            for await (index, clipURL, error) in group {
                if Task.isCancelled || session.startedAt != sourceSessionStart {
                    log.debug("Clip preparation stopped: task cancelled or session changed")
                    isPreparingClips = false
                    return
                }
                if let clipURL {
                    self.session.deliveries[index].videoURL = clipURL
                    self.session.deliveries[index].thumbnail = ClipThumbnailGenerator.releaseThumbnail(from: clipURL, releaseOffset: preRoll)
                    self.session.deliveries[index].status = .queued
                    self.deepAnalysisStatusByDelivery[self.session.deliveries[index].id] = DeliveryDeepAnalysisStatus(
                        stage: .idle,
                        elapsedSeconds: 0,
                        statusMessage: "",
                        failureMessage: nil
                    )
                    log.debug("Clip prepared for D\(index + 1): file=\(clipURL.lastPathComponent, privacy: .public)")
                    if self.liveService.isConnected {
                        await self.liveService.sendContext("[CLIP READY for delivery \(index + 1)] Video clip extracted and ready for analysis.")
                    }
                } else {
                    self.session.deliveries[index].status = .failed
                    let message = error?.localizedDescription ?? "Clip preparation failed."
                    self.deepAnalysisStatusByDelivery[self.session.deliveries[index].id] = DeliveryDeepAnalysisStatus(
                        stage: .failed,
                        elapsedSeconds: 0,
                        statusMessage: "",
                        failureMessage: message
                    )
                    log.error("D\(index + 1) clip extraction failed: \(message)")
                }
                let completed = await clipCounter.increment()
                let clippingProgress = Double(completed) / total
                self.clipPreparationProgress = 0.5 + (clippingProgress * 0.5)
                self.clipPreparationStatusMessage = "Clipping delivery \(completed) of \(Int(total))..."
            }
        }

        if Task.isCancelled || session.startedAt != sourceSessionStart {
            log.debug("Clip preparation ignored finalization due to cancellation/session change")
            isPreparingClips = false
            return
        }
        let readyCount = session.deliveries.filter { $0.videoURL != nil }.count
        if readyCount > 0 {
            clipPreparationStatusMessage = "Delivery clips ready (\(readyCount))."
        } else {
            clipPreparationStatusMessage = "No clips were produced."
        }
        clipPreparationProgress = 1
        isPreparingClips = false
        log.debug("Clip preparation completed: progress=\(self.clipPreparationProgress, privacy: .public)")
        refreshSessionSummary()

        // Connect review agent if not already connected (imported recordings reach here
        // without a prior endSession call, so the review agent hasn't been spun up yet).
        if matePhase != .postSessionReview && readyCount > 0 && WBConfig.enableLiveAPI {
            do {
                try audioManager.configure()
                try audioManager.startPlaybackEngine()
            } catch {
                log.error("Audio setup for review agent failed: \(error.localizedDescription, privacy: .public)")
            }
            await connectReviewAgent()
        }
    }

    private func detectDeliveryCandidatesWithGemini(
        recordingURL: URL,
        recordingDuration: Double,
        sourceSessionStart: Date?
    ) async -> [DeliveryTimestampCandidate] {
        let primaryCandidates = await runGeminiSegmentScan(
            recordingURL: recordingURL,
            recordingDuration: recordingDuration,
            sourceSessionStart: sourceSessionStart,
            segmentDuration: WBConfig.deliveryDetectionSegmentDurationSeconds,
            segmentOverlap: WBConfig.deliveryDetectionSegmentOverlapSeconds,
            highRecall: false,
            exportPresetName: AVAssetExportPresetMediumQuality,
            progressStart: 0.0,
            progressEnd: 0.45,
            label: "primary"
        )
        guard primaryCandidates.isEmpty else {
            return primaryCandidates
        }

        log.warning("Primary Gemini segment scan returned zero deliveries. Running high-recall fallback scan.")
        clipPreparationStatusMessage = "No clear releases in pass 1. Running high-recall scan..."
        return await runGeminiSegmentScan(
            recordingURL: recordingURL,
            recordingDuration: recordingDuration,
            sourceSessionStart: sourceSessionStart,
            segmentDuration: WBConfig.deliveryDetectionFallbackSegmentDurationSeconds,
            segmentOverlap: WBConfig.deliveryDetectionFallbackSegmentOverlapSeconds,
            highRecall: true,
            exportPresetName: AVAssetExportPresetHighestQuality,
            progressStart: 0.12,
            progressEnd: 0.45,
            label: "fallback"
        )
    }

    private func runGeminiSegmentScan(
        recordingURL: URL,
        recordingDuration: Double,
        sourceSessionStart: Date?,
        segmentDuration: Double,
        segmentOverlap: Double,
        highRecall: Bool,
        exportPresetName: String,
        progressStart: Double,
        progressEnd: Double,
        label: String
    ) async -> [DeliveryTimestampCandidate] {
        let windows = DeliveryBatchPlanner.scheduleSegments(
            totalDuration: recordingDuration,
            segmentDuration: segmentDuration,
            segmentOverlap: segmentOverlap
        )
        log.debug(
            "Gemini \(label, privacy: .public) segment scan scheduled: windows=\(windows.count), duration=\(recordingDuration, privacy: .public)s, segment=\(segmentDuration, privacy: .public)s, overlap=\(segmentOverlap, privacy: .public)s, highRecall=\(highRecall)"
        )

        guard !windows.isEmpty else {
            log.warning("Gemini \(label, privacy: .public) segment scan skipped: no windows scheduled")
            return []
        }

        var rawCandidates: [DeliveryTimestampCandidate] = []
        let totalSegments = windows.count
        let progressSpan = max(progressEnd - progressStart, 0)

        for window in windows {
            if Task.isCancelled || session.startedAt != sourceSessionStart {
                return []
            }

            clipPreparationStatusMessage = "Detecting deliveries (\(label)) segment \(window.index + 1) of \(totalSegments)..."
            let segmentProgress = Double(window.index) / Double(max(totalSegments, 1))
            clipPreparationProgress = min(progressStart + (segmentProgress * progressSpan), progressEnd)

            do {
                let segmentURL = try await exportDetectionSegment(
                    from: recordingURL,
                    startTime: window.start,
                    duration: window.duration,
                    presetName: exportPresetName
                )
                defer { try? FileManager.default.removeItem(at: segmentURL) }

                let detections = try await analysisService.detectDeliveryTimestampsInSegment(
                    segmentURL: segmentURL,
                    segmentDuration: window.duration,
                    highRecall: highRecall
                )
                let mapped = detections.map { detection in
                    DeliveryTimestampCandidate(
                        timestamp: window.start + detection.localTimestamp,
                        confidence: detection.confidence,
                        source: .gemini
                    )
                }
                rawCandidates.append(contentsOf: mapped)
                let mappedPreview = Self.formatCandidateTimeline(mapped)
                log.debug(
                    "Gemini \(label, privacy: .public) segment \(window.index + 1)/\(totalSegments) detection complete: releases=\(mapped.count), window=[\(window.start, privacy: .public), \(window.end, privacy: .public)], candidates=[\(mappedPreview, privacy: .public)]"
                )
            } catch {
                log.error(
                    "Gemini \(label, privacy: .public) segment \(window.index + 1)/\(totalSegments) detection failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        clipPreparationProgress = progressEnd
        let merged = DeliveryBatchPlanner.mergeCandidates(
            candidates: rawCandidates,
            dedupeWindow: WBConfig.deliveryDetectionMergeWindowSeconds,
            sessionDuration: recordingDuration
        )
        log.debug(
            "Gemini \(label, privacy: .public) segment scan merged: raw=\(rawCandidates.count), merged=\(merged.count), timeline=[\(Self.formatCandidateTimeline(merged), privacy: .public)]"
        )
        return merged
    }

    private func rebuildDeliveriesFromDetectionCandidates(
        batchCandidates: [DeliveryTimestampCandidate],
        recordingOffset: Double,
        recordingDuration: Double
    ) {
        let previousDeliveries = session.deliveries
        let previousChallengeTargets = challengeTargetBySequence
        let mergeWindow = WBConfig.deliveryDetectionMergeWindowSeconds

        let liveCandidates = previousDeliveries.map { delivery in
            DeliveryTimestampCandidate(
                timestamp: max(delivery.timestamp - recordingOffset, 0),
                confidence: WBConfig.liveDetectionConfidence,
                source: .live
            )
        }
        log.debug(
            "Detection merge input live: count=\(liveCandidates.count), timeline=[\(Self.formatCandidateTimeline(liveCandidates), privacy: .public)]"
        )
        log.debug(
            "Detection merge input gemini: count=\(batchCandidates.count), timeline=[\(Self.formatCandidateTimeline(batchCandidates), privacy: .public)]"
        )

        let mergedCandidates = DeliveryBatchPlanner.mergeCandidates(
            candidates: liveCandidates + batchCandidates,
            dedupeWindow: mergeWindow,
            sessionDuration: recordingDuration
        )
        log.debug(
            "Detection merge output: count=\(mergedCandidates.count), timeline=[\(Self.formatCandidateTimeline(mergedCandidates), privacy: .public)]"
        )

        var consumedLiveIDs = Set<UUID>()
        var rebuilt: [Delivery] = []

        for candidate in mergedCandidates {
            let matched = previousDeliveries.first { delivery in
                guard !consumedLiveIDs.contains(delivery.id) else { return false }
                let liveRelativeTimestamp = max(delivery.timestamp - recordingOffset, 0)
                return abs(liveRelativeTimestamp - candidate.timestamp) <= mergeWindow
            }

            if let matched {
                consumedLiveIDs.insert(matched.id)
                var reused = matched
                reused.status = .clipping
                reused.videoURL = nil
                reused.thumbnail = nil
                reused.report = nil
                reused.speed = nil
                reused.tips = []
                reused.phases = nil
                reused.releaseTimestamp = nil
                rebuilt.append(reused)
            } else {
                let absoluteTimestamp = candidate.timestamp + recordingOffset
                rebuilt.append(
                    Delivery(
                        timestamp: absoluteTimestamp,
                        status: .clipping,
                        sequence: 0
                    )
                )
            }
        }

        rebuilt.sort { $0.timestamp < $1.timestamp }
        for index in rebuilt.indices {
            rebuilt[index].sequence = index + 1
        }
        session.deliveries = rebuilt

        if session.mode == .challenge {
            var remappedTargets: [Int: String] = [:]
            for delivery in rebuilt {
                guard let previous = previousDeliveries.first(where: { $0.id == delivery.id }),
                      let target = previousChallengeTargets[previous.sequence] else { continue }
                remappedTargets[delivery.sequence] = target
            }
            challengeTargetBySequence = remappedTargets
        }

        let validIDs = Set(rebuilt.map(\.id))
        deepAnalysisStatusByDelivery = deepAnalysisStatusByDelivery.filter { validIDs.contains($0.key) }
        deepAnalysisArtifactsByDelivery = deepAnalysisArtifactsByDelivery.filter { validIDs.contains($0.key) }
        challengeEvaluatedDeliveries.formIntersection(validIDs)

        for delivery in rebuilt where deepAnalysisStatusByDelivery[delivery.id] == nil {
            deepAnalysisStatusByDelivery[delivery.id] = DeliveryDeepAnalysisStatus(
                stage: .idle,
                elapsedSeconds: 0,
                statusMessage: "",
                failureMessage: nil
            )
        }

        let liveOnlyCount = previousDeliveries.count
        let batchOnlyCount = max(rebuilt.count - consumedLiveIDs.count, 0)
        log.debug(
            "Detection merge complete: live=\(liveOnlyCount), batch=\(batchCandidates.count), merged=\(rebuilt.count), batchOnlyAdded=\(batchOnlyCount)"
        )
    }

    private func exportDetectionSegment(
        from recordingURL: URL,
        startTime: Double,
        duration: Double,
        presetName: String = AVAssetExportPresetMediumQuality
    ) async throws -> URL {
        let asset = AVURLAsset(url: recordingURL)
        let safeDuration = max(duration, 0.5)
        let outputFileType: AVFileType = presetName == AVAssetExportPresetHighestQuality ? .mov : .mp4
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("segment_\(UUID().uuidString)")
            .appendingPathExtension(outputFileType == .mov ? "mov" : "mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ClipError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: safeDuration, preferredTimescale: 600)
        )

        await exportSession.export()
        guard exportSession.status == .completed else {
            throw exportSession.error ?? ClipError.exportFailed
        }
        return outputURL
    }

    // MARK: - On-Demand Deep Analysis

    func deepAnalysisStatus(for deliveryID: UUID) -> DeliveryDeepAnalysisStatus {
        deepAnalysisStatusByDelivery[deliveryID] ?? DeliveryDeepAnalysisStatus()
    }

    func deepAnalysisArtifacts(for deliveryID: UUID) -> DeliveryDeepAnalysisArtifacts? {
        let result = deepAnalysisArtifactsByDelivery[deliveryID]
        if result == nil {
            log.warning("Deep analysis artifacts not found for \(deliveryID.uuidString.prefix(8), privacy: .public). Available keys: \(self.deepAnalysisArtifactsByDelivery.keys.map { String($0.uuidString.prefix(8)) })")
        }
        return result
    }

    // MARK: - Composited Video Export

    func exportComposited(for deliveryID: UUID) async {
        guard compositedExportStatus != .saving else { return }
        compositedExportStatus = .saving

        guard let delivery = session.deliveries.first(where: { $0.id == deliveryID }),
              let clipURL = delivery.videoURL else {
            log.error("Export composited: no clip URL for delivery \(deliveryID.uuidString.prefix(8), privacy: .public)")
            compositedExportStatus = .failed("No clip available")
            return
        }

        let artifacts = deepAnalysisArtifactsByDelivery[deliveryID]
        guard let poseFrames = artifacts?.poseFrames, !poseFrames.isEmpty else {
            log.error("Export composited: no pose frames for delivery \(deliveryID.uuidString.prefix(8), privacy: .public)")
            compositedExportStatus = .failed("Run deep analysis first")
            return
        }

        let input = VideoCompositor.Input(
            clipURL: clipURL,
            poseFrames: poseFrames,
            expertAnalysis: artifacts?.expertAnalysis,
            phases: delivery.phases ?? [],
            speedKph: delivery.speedKph,
            dnaMatch: delivery.dnaMatches?.first
        )

        do {
            let compositor = VideoCompositor()
            let outputURL = try await compositor.composite(input)
            log.info("Composited export complete: \(outputURL.lastPathComponent, privacy: .public)")

            // Save to Photos
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: outputURL, options: nil)
            }
            compositedExportStatus = .saved
            log.info("Composited video saved to Photos")
        } catch {
            log.error("Composited export failed: \(error.localizedDescription, privacy: .public)")
            compositedExportStatus = .failed(error.localizedDescription)
        }
    }

    func runDeepAnalysisIfNeeded(for deliveryID: UUID) async {
        if deepAnalysisTasksByDelivery[deliveryID] != nil {
            log.debug("Deep analysis already running: deliveryID=\(deliveryID.uuidString, privacy: .public)")
            return
        }
        log.debug("Deep analysis requested: deliveryID=\(deliveryID.uuidString, privacy: .public)")
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runDeepAnalysis(for: deliveryID)
        }
        deepAnalysisTasksByDelivery[deliveryID] = task
        await task.value
    }

    func requestChipGuidance(for deliveryID: UUID, chip: String) async -> ChipGuidanceResponse {
        guard let delivery = session.deliveries.first(where: { $0.id == deliveryID }) else {
            log.debug("Chip guidance skipped: delivery not found, chip=\(chip, privacy: .public)")
            return ChipGuidanceResponse(
                reply: "That delivery is no longer available.",
                action: "none",
                phaseName: nil,
                focusStart: nil,
                focusEnd: nil,
                playbackRate: nil
            )
        }

        let summary = delivery.report ?? "Delivery analysis in progress."
        let phases = delivery.phases ?? []
        log.debug("Chip guidance requested: deliveryID=\(deliveryID.uuidString, privacy: .public), chip=\(chip, privacy: .public), phases=\(phases.count)")
        do {
            let guidance = try await analysisService.generateChipGuidance(
                chip: chip,
                deliverySummary: summary,
                phases: phases
            )
            var artifacts = deepAnalysisArtifactsByDelivery[deliveryID] ?? DeliveryDeepAnalysisArtifacts()
            artifacts.chipReply = guidance.reply
            deepAnalysisArtifactsByDelivery[deliveryID] = artifacts
            log.debug("Chip guidance success: action=\(guidance.action, privacy: .public)")
            return guidance
        } catch {
            log.error("Chip guidance failed, using fallback: \(error.localizedDescription, privacy: .public)")
            let fallback = ChipGuidanceResponse(
                reply: "Focusing that phase now.",
                action: "focus",
                phaseName: phases.first?.name,
                focusStart: phases.first?.clipTimestamp,
                focusEnd: (phases.first?.clipTimestamp ?? 2.0) + 0.8,
                playbackRate: 0.45
            )
            var artifacts = deepAnalysisArtifactsByDelivery[deliveryID] ?? DeliveryDeepAnalysisArtifacts()
            artifacts.chipReply = fallback.reply
            deepAnalysisArtifactsByDelivery[deliveryID] = artifacts
            return fallback
        }
    }

    private enum DeepComponentResult {
        case detailed(Result<DeliveryDeepAnalysisResult, Error>)
        case pose(Result<[FramePoseLandmarks], Error>)
        case challenge(Result<ChallengeResult, Error>, target: String)
    }

    private func runDeepAnalysis(for deliveryID: UUID) async {
        guard let index = session.deliveries.firstIndex(where: { $0.id == deliveryID }) else {
            deepAnalysisTasksByDelivery[deliveryID] = nil
            return
        }
        log.debug("Deep analysis started: delivery=\(index + 1), mode=\(self.session.mode.rawValue, privacy: .public)")
        let poseFPS = WBConfig.poseExtractionFPS
        guard let clipURL = session.deliveries[index].videoURL else {
            deepAnalysisStatusByDelivery[deliveryID] = DeliveryDeepAnalysisStatus(
                stage: .failed,
                elapsedSeconds: 0,
                statusMessage: "",
                failureMessage: "Clip is not ready yet."
            )
            deepAnalysisTasksByDelivery[deliveryID] = nil
            return
        }

        startTelemetry(for: deliveryID)
        session.deliveries[index].status = .analyzing

        // Inform the buddy that analysis is starting
        if liveService.isConnected {
            await liveService.sendContext("[ANALYZING delivery \(index + 1)] Deep analysis in progress — will share results when ready.")
        }

        // Speed estimation (if calibration available)
        var speedContext: GeminiAnalysisService.SpeedContext?
        if let calibration = session.calibration {
            do {
                let deliveryTs = session.deliveries[index].releaseTimestamp ?? WBConfig.clipPreRoll
                let estimate = try await speedEstimationService.estimateSpeed(
                    clipURL: clipURL,
                    calibration: calibration,
                    deliveryTimestamp: deliveryTs
                )
                let margin = estimate.errorMarginKph ?? 5.0
                if margin < 5.0 {
                    session.deliveries[index].speedKph = estimate.kph
                    session.deliveries[index].speedErrorMarginKph = margin
                    session.deliveries[index].speedConfidence = estimate.confidence
                    session.deliveries[index].speedMethod = estimate.method
                    log.info("Speed estimated for D\(index + 1): \(String(format: "%.1f", estimate.kph)) ±\(String(format: "%.1f", margin)) kph")
                } else {
                    log.info("Speed suppressed for D\(index + 1): ±\(String(format: "%.1f", margin)) kph too imprecise")
                }
                speedContext = GeminiAnalysisService.SpeedContext(
                    kph: estimate.kph,
                    errorMarginKph: margin,
                    method: estimate.method.rawValue,
                    fps: calibration.recordingFPS
                )
            } catch {
                log.debug("Speed estimation failed for D\(index + 1): \(error.localizedDescription, privacy: .public)")
            }
        }

        var detailedResult: DeliveryDeepAnalysisResult?
        var dnaResult: BowlingDNA?
        var poseFrames: [FramePoseLandmarks] = []
        var poseFailureReason: String?
        var challengeText: String?

        let challengeTarget: String? = {
            guard session.mode == .challenge else { return nil }
            guard !challengeEvaluatedDeliveries.contains(deliveryID) else { return nil }
            return challengeTargetBySequence[session.deliveries[index].sequence]
        }()

        await withTaskGroup(of: DeepComponentResult.self) { group in
            // Deep analysis + DNA extraction in ONE Gemini call (same video, same response)
            group.addTask { [analysisService] in
                do {
                    let deep = try await analysisService.analyzeDeliveryDeep(clipURL: clipURL, speedContext: speedContext)
                    return .detailed(.success(deep))
                } catch {
                    return .detailed(.failure(error))
                }
            }

            group.addTask { [clipPoseExtractor] in
                do {
                    let frames = try await clipPoseExtractor.extractFrames(from: clipURL, targetFPS: poseFPS)
                    return .pose(.success(frames))
                } catch {
                    return .pose(.failure(error))
                }
            }

            if let target = challengeTarget {
                group.addTask { [analysisService] in
                    do {
                        let result = try await analysisService.evaluateChallenge(clipURL: clipURL, target: target)
                        return .challenge(.success(result), target: target)
                    } catch {
                        return .challenge(.failure(error), target: target)
                    }
                }
            }

            for await component in group {
                switch component {
                case .detailed(.success(let result)):
                    detailedResult = result
                    dnaResult = result.dna // DNA extracted from same Gemini call
                    log.debug("Deep analysis component ready: detailed delivery=\(index + 1), dna=\(result.dna != nil)")
                case .detailed(.failure(let error)):
                    log.error("Deep analysis failed for D\(index + 1): \(error.localizedDescription)")
                case .pose(.success(let frames)):
                    poseFrames = frames
                    poseFailureReason = nil
                    log.debug("Deep analysis component ready: pose delivery=\(index + 1), frames=\(frames.count)")
                case .pose(.failure(let error)):
                    poseFailureReason = error.localizedDescription
                    log.debug("Pose extraction failed for D\(index + 1): \(error.localizedDescription, privacy: .public)")
                case .challenge(.success(let result), let target):
                    self.session.recordChallengeResult(hit: result.matchesTarget)
                    self.challengeEvaluatedDeliveries.insert(deliveryID)
                    challengeText = ChallengeEngine.formatResult(target: target, result: result)
                    log.debug("Deep analysis component ready: challenge delivery=\(index + 1), hit=\(result.matchesTarget)")
                case .challenge(.failure(let error), _):
                    log.debug("Challenge evaluation failed for D\(index + 1): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        stopTelemetry(for: deliveryID)

        guard let detailedResult else {
            session.deliveries[index].status = .failed
            deepAnalysisStatusByDelivery[deliveryID] = DeliveryDeepAnalysisStatus(
                stage: .failed,
                elapsedSeconds: 0,
                statusMessage: "",
                failureMessage: "Detailed analysis failed. Tap to retry."
            )
            deepAnalysisTasksByDelivery[deliveryID] = nil
            log.debug("Deep analysis ended with failure: delivery=\(index + 1)")

            // Tell the live agent about the failure so it can inform the bowler
            if liveService.isConnected {
                await liveService.sendContext(
                    "[ANALYSIS FAILED for delivery \(index + 1)] The deep analysis timed out or failed. " +
                    "The bowler can tap 'Retry' on the delivery card. Let them know briefly — don't dwell on it."
                )
            }
            return
        }

        var report = detailedResult.summary
        if let challengeText, !challengeText.isEmpty {
            report = report.isEmpty ? challengeText : "\(report) • \(challengeText)"
        }

        session.deliveries[index].report = report
        session.deliveries[index].speed = detailedResult.paceEstimate
        session.deliveries[index].phases = detailedResult.phases
        session.deliveries[index].status = .success

        // Gemini visual assessment: if speed confidence is very low, suppress the speed display
        if let geminiConf = detailedResult.speedConfidence, geminiConf < 0.4, session.deliveries[index].speedKph != nil {
            log.info("Speed suppressed for D\(index + 1): Gemini visual confidence \(String(format: "%.2f", geminiConf)) too low")
            session.deliveries[index].speedKph = nil
            session.deliveries[index].speedErrorMarginKph = nil
        }

        if let dna = dnaResult {
            session.deliveries[index].dna = dna
            session.deliveries[index].dnaMatches = BowlingDNAMatcher.match(userDNA: dna)
        }

        var artifacts = deepAnalysisArtifactsByDelivery[deliveryID] ?? DeliveryDeepAnalysisArtifacts()
        artifacts.poseFrames = poseFrames
        if poseFrames.isEmpty {
            artifacts.poseFailureReason = poseFailureReason ?? "No confident pose landmarks detected in the delivery clip. Try closer framing and stronger lighting."
            log.error("Pose extraction failed for D\(index + 1): \(artifacts.poseFailureReason!, privacy: .public)")
        } else {
            artifacts.poseFailureReason = nil
            log.debug("Pose extraction succeeded for D\(index + 1): \(poseFrames.count) frames")
        }
        artifacts.expertAnalysis = detailedResult.expertAnalysis ?? ExpertAnalysisBuilder.build(from: detailedResult.phases)
        deepAnalysisArtifactsByDelivery[deliveryID] = artifacts
        log.debug("Stored deep analysis artifacts for D\(index + 1): poseFrames=\(poseFrames.count), poseFailure=\(poseFailureReason ?? "none", privacy: .public)")

        deepAnalysisStatusByDelivery[deliveryID] = DeliveryDeepAnalysisStatus(
            stage: .ready,
            elapsedSeconds: 0,
            statusMessage: "Deep analysis ready",
            failureMessage: nil
        )

        deepAnalysisTasksByDelivery[deliveryID] = nil
        log.debug("Deep analysis completed: delivery=\(index + 1), phases=\(detailedResult.phases.count), poseFrames=\(poseFrames.count), dnaAvailable=\(dnaResult != nil), poseFailureReason=\(poseFailureReason ?? "-", privacy: .public)")

        // Feed analysis results back to the buddy for natural spoken debrief
        if liveService.isConnected {
            var feedbackParts: [String] = ["[ANALYSIS COMPLETE for delivery \(index + 1)]"]
            feedbackParts.append("Summary: \(detailedResult.summary)")
            if let speedKph = session.deliveries[index].speedKph, let margin = session.deliveries[index].speedErrorMarginKph {
                feedbackParts.append("Estimated speed: \(String(format: "%.0f", speedKph)) ±\(String(format: "%.0f", margin)) kph (video-based estimate, not radar)")
            } else if let speedKph = session.deliveries[index].speedKph {
                feedbackParts.append("Estimated speed: ~\(String(format: "%.0f", speedKph)) kph (video-based estimate)")
            } else if !detailedResult.paceEstimate.isEmpty {
                feedbackParts.append("Pace estimate: \(detailedResult.paceEstimate)")
            }

            // Detailed phase-by-phase breakdown for technical analysis
            for phase in detailedResult.phases {
                let status = phase.isGood ? "GOOD" : "NEEDS WORK"
                var phaseInfo = "\(phase.name) [\(status)]: \(phase.observation)"
                if !phase.tip.isEmpty {
                    phaseInfo += " — Fix: \(phase.tip)"
                }
                feedbackParts.append(phaseInfo)
            }

            if let match = session.deliveries[index].dnaMatches?.first {
                feedbackParts.append("DNA match: \(match.bowlerName) (\(match.country)) at \(Int(match.similarityPercent))%. Closest phase: \(match.closestPhase). Biggest difference: \(match.biggestDifference).")
            }
            if let challengeText {
                feedbackParts.append("Challenge result: \(challengeText)")
            }
            if let drills = detailedResult.drills, !drills.isEmpty {
                let drillSummary = drills.map { "\($0.name): \($0.why)" }.joined(separator: ". ")
                feedbackParts.append("Drills: \(drillSummary)")
            }

            feedbackParts.append("Give ONE specific cue for the next ball. One sentence. Be real.")
            await liveService.sendContext(feedbackParts.joined(separator: " "))

            // Rotate to next challenge target after evaluation
            if challengeText != nil {
                await issueNextChallengeTarget()
            }

            // Also feed to review agent if in review mode
            if matePhase == .postSessionReview {
                await feedAnalysisToReviewAgent(deliveryIndex: index)
            }
        }

        refreshSessionSummary()
    }

    private func startTelemetry(for deliveryID: UUID) {
        stopTelemetry(for: deliveryID)
        log.debug("Telemetry started: deliveryID=\(deliveryID.uuidString, privacy: .public)")
        deepAnalysisStatusByDelivery[deliveryID] = DeliveryDeepAnalysisStatus(
            stage: .running,
            elapsedSeconds: 0,
            statusMessage: SessionResultsPlanner.telemetryMessage(elapsedSeconds: 0),
            failureMessage: nil
        )
        telemetryTasksByDelivery[deliveryID] = Task { [weak self] in
            var elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                elapsed += 2
                guard let self else { return }
                guard var status = self.deepAnalysisStatusByDelivery[deliveryID], status.stage == .running else { return }
                status.elapsedSeconds = elapsed
                status.statusMessage = SessionResultsPlanner.telemetryMessage(elapsedSeconds: elapsed)
                self.deepAnalysisStatusByDelivery[deliveryID] = status
            }
        }
    }

    private func stopTelemetry(for deliveryID: UUID) {
        telemetryTasksByDelivery[deliveryID]?.cancel()
        telemetryTasksByDelivery[deliveryID] = nil
        log.debug("Telemetry stopped: deliveryID=\(deliveryID.uuidString, privacy: .public)")
    }

    private func cancelAllDeepAnalysisTasks(resetState: Bool) {
        log.debug("Canceling deep-analysis tasks: running=\(self.deepAnalysisTasksByDelivery.count), telemetry=\(self.telemetryTasksByDelivery.count), reset=\(resetState)")
        for (_, task) in deepAnalysisTasksByDelivery {
            task.cancel()
        }
        deepAnalysisTasksByDelivery.removeAll()

        for (_, task) in telemetryTasksByDelivery {
            task.cancel()
        }
        telemetryTasksByDelivery.removeAll()

        if resetState {
            deepAnalysisStatusByDelivery.removeAll()
            deepAnalysisArtifactsByDelivery.removeAll()
        }
    }

    private func refreshSessionSummary() {
        let analyzed = session.deliveries.filter { $0.status == .success }
        let dominant: PaceBand = {
            let speeds = analyzed.compactMap { $0.speed?.lowercased() }
            let quick = speeds.filter { $0.contains("quick") }.count
            let slow = speeds.filter { $0.contains("slow") || $0.contains("spin") }.count
            if quick > slow && quick > 0 { return .quick }
            if slow > quick && slow > 0 { return .slow }
            return .medium
        }()

        let paceDistribution: [PaceBand: Int] = [
            .quick: analyzed.filter { ($0.speed ?? "").lowercased().contains("quick") }.count,
            .medium: analyzed.filter {
                let value = ($0.speed ?? "").lowercased()
                return value.contains("medium") || value.contains("pace")
            }.count,
            .slow: analyzed.filter {
                let value = ($0.speed ?? "").lowercased()
                return value.contains("slow") || value.contains("spin")
            }.count
        ]

        let observation: String = {
            if session.deliveryCount == 0 {
                return "No deliveries detected in this session."
            }
            if analyzed.isEmpty {
                return "Tap Deep Analysis on a delivery to generate expert insights."
            }
            return analyzed.last?.report ?? "Tap Deep Analysis on a delivery to generate expert insights."
        }()
        let challengeScore = session.mode == .challenge && session.challengeTotal > 0 ? session.challengeScoreText : nil
        session.summary = SessionSummary(
            totalDeliveries: session.deliveryCount,
            durationMinutes: max(session.duration / 60.0, 0),
            dominantPace: dominant,
            paceDistribution: paceDistribution,
            keyObservation: observation,
            challengeScore: challengeScore
        )
        log.debug("Session summary refreshed: analyzed=\(analyzed.count), total=\(self.session.deliveryCount), dominant=\(dominant.label, privacy: .public)")
    }

    private func issueNextChallengeTarget(isInitial: Bool = false) async {
        guard session.mode == .challenge, WBConfig.enableChallengeMode else { return }

        let target = challengeEngine.nextTarget()
        session.currentChallenge = target
        currentChallengeTarget = target

        if liveService.isConnected {
            await liveService.speakChallenge(target: target)
        } else {
            let prefix = isInitial ? "Challenge target" : "Next target"
            tts.announceChallenge(target: "\(prefix): \(target).")
        }

        await maybeSendProactiveGreetingIfNeeded()
    }

    private func maybeSendProactiveGreetingIfNeeded() async {
        guard session.isActive else { return }
        guard shouldSendProactiveGreeting, !didSendProactiveGreeting else { return }
        guard liveService.isConnected else { return }

        didSendProactiveGreeting = true
        flowPhase = .starting

        // Single natural greeting — the system prompt handles all conversational flow autonomously.
        await liveService.sendContext("""
        [SESSION STARTED] Look at the video feed. Assess what you actually see before speaking. \
        Do NOT assume anything — no nets, no stumps, no environment. Describe nothing you haven't seen. \
        Wait 2-3 seconds to process the video before your first word. \
        Then: one short greeting. Ask what they want to work on. Ask how long they have. \
        Call set_session_duration when they tell you (default 5 minutes if they don't say). \
        If you see stumps in the video, call show_alignment_boxes — boxes will appear on screen. \
        If no stumps visible, say nothing about stumps. \
        Keep every response to one sentence. Be real. Be brief.
        """)
    }

    // MARK: - Review Agent (Fresh Dedicated Voice for Post-Session Walkthrough)

    /// Build a dedicated review agent system prompt with all analysis data baked in.
    private func buildReviewAgentPrompt() -> String {
        let deliveries = session.deliveries
        let count = deliveries.count
        let mode = session.mode

        var deliveryDetails: [String] = []
        for (i, d) in deliveries.enumerated() {
            let seq = i + 1
            var lines: [String] = ["Delivery \(seq):"]
            if let kph = d.speedKph, let margin = d.speedErrorMarginKph {
                lines.append("  Estimated speed: \(String(format: "%.0f", kph)) ±\(String(format: "%.0f", margin)) kph (video-based)")
            } else if let kph = d.speedKph {
                lines.append("  Estimated speed: ~\(String(format: "%.0f", kph)) kph (video-based)")
            }
            if let report = d.report, !report.isEmpty {
                lines.append("  Report: \(report)")
            }
            if let phases = d.phases, !phases.isEmpty {
                for phase in phases {
                    var phaseLabel = "  \(phase.name) [\(phase.status)]"
                    if let ts = phase.clipTimestamp {
                        phaseLabel += " @ \(String(format: "%.1f", ts))s in clip"
                    }
                    lines.append(phaseLabel)
                    if !phase.observation.isEmpty {
                        lines.append("    \(phase.observation)")
                    }
                    if !phase.tip.isEmpty {
                        lines.append("    Drill: \(phase.tip)")
                    }
                }
            }
            if let matches = d.dnaMatches, !matches.isEmpty {
                let top = matches[0]
                lines.append("  DNA match: \(top.bowlerName) (\(top.country), \(top.era)) — \(Int(top.similarityPercent))% similar")
                lines.append("    Style: \(top.style)")
                lines.append("    Closest phase: \(top.closestPhase)")
                lines.append("    Biggest difference: \(top.biggestDifference)")
                if !top.signatureTraits.isEmpty {
                    lines.append("    Signature traits: \(top.signatureTraits.joined(separator: "; "))")
                }
                if matches.count > 1 {
                    let others = matches.dropFirst().prefix(2).map { "\($0.bowlerName) \(Int($0.similarityPercent))%" }
                    lines.append("    Also resembles: \(others.joined(separator: ", "))")
                }
            }
            if let dna = d.dna {
                var traits: [String] = []
                if let ap = dna.armPath { traits.append("arm: \(ap.rawValue)") }
                if let wp = dna.wristPosition { traits.append("wrist: \(wp.rawValue)") }
                if let ga = dna.gatherAlignment { traits.append("alignment: \(ga.rawValue)") }
                if let rh = dna.releaseHeight { traits.append("release: \(rh.rawValue)") }
                if let ft = dna.followThroughDirection { traits.append("follow-through: \(ft.rawValue)") }
                if let hs = dna.headStability { traits.append("head: \(hs.rawValue)") }
                if !traits.isEmpty {
                    lines.append("  Action shape: \(traits.joined(separator: ", "))")
                }
            }
            if let target = challengeTargetBySequence[seq] {
                lines.append("  Challenge target: \(target)")
            }
            deliveryDetails.append(lines.joined(separator: "\n"))
        }

        let allDeliveries = deliveryDetails.joined(separator: "\n\n")

        // Speed summary
        let speeds = deliveries.compactMap(\.speedKph)
        var speedSummary = ""
        if let minS = speeds.min(), let maxS = speeds.max() {
            let avg = speeds.reduce(0, +) / Double(speeds.count)
            speedSummary = "Speed: avg \(String(format: "%.1f", avg)) kph, range \(String(format: "%.1f", minS))–\(String(format: "%.1f", maxS)) kph"
        }

        // Challenge summary
        var challengeSummary = ""
        if mode == .challenge && session.challengeTotal > 0 {
            let pct = session.challengeTotal > 0 ? Int(Double(session.challengeHits) / Double(session.challengeTotal) * 100) : 0
            challengeSummary = "Challenge score: \(session.challengeHits)/\(session.challengeTotal) (\(pct)%)"
        }

        // Cross-delivery patterns for the agent to reference
        var patternNotes: [String] = []
        let phaseNames = Set(deliveries.compactMap(\.phases).flatMap { $0 }.map(\.name))
        for phaseName in phaseNames {
            let needsWork = deliveries.filter { d in
                d.phases?.first(where: { $0.name == phaseName && !$0.isGood }) != nil
            }
            if needsWork.count >= 2 {
                let seqs = needsWork.compactMap { d in deliveries.firstIndex(where: { $0.id == d.id }).map { $0 + 1 } }
                patternNotes.append("Recurring issue — \(phaseName) needs work in deliveries \(seqs.map(String.init).joined(separator: ", "))")
            }
        }

        // DNA consistency
        let topMatches = deliveries.compactMap(\.dnaMatches?.first)
        if topMatches.count >= 2 {
            let names = topMatches.map(\.bowlerName)
            let unique = Set(names)
            if unique.count == 1 {
                patternNotes.append("Consistent DNA — matched \(names[0]) across all analyzed deliveries")
            } else {
                let grouped = Dictionary(grouping: names, by: { $0 }).sorted { $0.value.count > $1.value.count }
                let desc = grouped.prefix(3).map { "\($0.key) ×\($0.value.count)" }.joined(separator: ", ")
                patternNotes.append("DNA variation: \(desc)")
            }
        }

        let patternsBlock = patternNotes.isEmpty ? "" : "\nPATTERNS DETECTED:\n\(patternNotes.map { "- \($0)" }.joined(separator: "\n"))"

        let personaLine: String = {
            switch WBConfig.matePersona.personaStyle {
            case .aussie: return "Speak with a casual Australian accent. Cricket slang welcome."
            case .tamil: return "SPEAK ENTIRELY IN TAMIL. Cricket terms in English."
            case .tanglish: return "Speak in Tanglish — natural Tamil-English mix."
            default: return "Speak in clear, warm English."
            }
        }()

        return """
        You are the same bowling mate — the session just ended and now you're looking at the \
        results together. Do NOT re-greet or re-introduce yourself. Do NOT say "welcome back" or \
        "let's review." Just continue naturally as if you're still in the same conversation.

        The bowler is wearing earbuds. They cannot touch the phone. Everything is voice. \
        You are their expert mate — not a presenter reading slides.

        \(personaLine)

        SESSION DATA (what you know so far):
        Total deliveries: \(count)
        Mode: \(mode == .challenge ? "Challenge" : "Free Play")
        \(speedSummary)
        \(challengeSummary)
        \(patternsBlock)

        \(allDeliveries)

        HOW YOU BEHAVE — like a real human expert, not a template:

        YOUR CONNECTION IS PERMANENT:
        You stay connected for as long as the bowler is on the results screen. You are ALWAYS \
        listening and watching. There is NO timeout — you don't end the conversation unless \
        the bowler says "done" or "thanks". You are like a mate sitting next to them.

        WHEN YOU FIRST CONNECT:
        Analysis may still be running. You'll receive a message telling you the current state. \
        If analysis isn't done yet, DON'T just wait silently. Give a running commentary: \
        - What you're seeing on screen ("Clip 1 is loading, I can see the run-up...")
        - Tease what you'll look at ("I want to check that front arm position...")
        - React to the video as it plays — like a mate watching cricket together
        - USE PLAYBACK TOOLS while waiting: pause at interesting frames, slow-mo the release, \
          seek to specific moments. Show the bowler what you're noticing in real time.
        When the bowler talks to you, respond immediately. When they're quiet, keep the \
        commentary going — you're the expert filling the silence with insight.

        WHEN ANALYSIS DATA ARRIVES:
        You will receive "[ANALYSIS READY — delivery N]" messages with FULL data for each delivery: \
        phase breakdown (name, status, observation, drill, clip timestamp), DNA match (bowler name, \
        country, era, similarity %, closest phase, biggest difference, signature traits, action shape), \
        speed, challenge results. READ THIS DATA CAREFULLY. It's the actual analysis — not a summary. \
        You should know what every phase says, what the DNA comparison means, what drill was suggested.

        When "[ALL DELIVERIES ANALYZED]" arrives, you have the complete session picture — speed trends, \
        recurring issues, DNA consistency, best delivery. NOW you can give the full walkthrough.

        HOW YOU WALK THROUGH RESULTS:
        You're not reading a report. You're an expert who's just seen the data and is forming an opinion. \
        - Start with what strikes you most. Maybe it's a recurring fault. Maybe it's a great DNA match. \
        Maybe it's a speed drop in the second half. Lead with what matters, not delivery 1.
        - Ask the bowler what they want to see: "Want to go through each one, or jump to something specific?"
        - When discussing a delivery, USE THE PLAYBACK TOOLS. Seek to the clip timestamp for a phase. \
        Slow-mo the release. Show them what you're talking about — don't just describe it.
        - Reference the DNA match properly: who the match is, WHY they match (which phase is closest), \
        WHERE they diverge (biggest difference), and what the famous bowler's signature traits are. \
        Make it mean something: "You're 82% Starc — that's the high arm and the steep bounce angle. \
        The difference is follow-through — Starc drives across hard, you're falling away. Fix that \
        and you'd be even closer."
        - Reference drills from the analysis: "The analysis suggests bowling from a standing start \
        to isolate the brace — want to try that next session?"
        - Connect dots across deliveries: "Your front arm was flagged on deliveries 2, 4, and 5 — \
        that's the pattern. Ball 3 was the cleanest because your front arm pulled down properly."

        TOOLS:
        - `navigate_delivery`: move between deliveries (next / previous / goto index).
        - `control_playback`:
          * "play" — resume normal speed. Use rate "1.0" for normal, "2.0" for fast.
          * "pause" — freeze frame
          * "slow_mo" with rate "0.25" (ultra slow-mo) or "0.5" (half speed)
          * "seek" with timestamp "2.1" — jump to moment in clip (0.0–5.0s)
          * "focus_phase" with timestamp and rate — loop a specific moment in slow-mo
        - Use these WHEN YOU'RE MAKING A POINT. "Let me show you what I mean" → seek + slow_mo. \
        Don't use them robotically on every delivery. Use them when the visual matters.
        - CRITICAL: When the user asks you to change speed, pause, play, slow-mo, or any \
        playback control — IMMEDIATELY call `control_playback` with the right action. \
        Don't just acknowledge — execute it. Examples:
          * "Set to half speed" → call control_playback(action: "slow_mo", rate: "0.5")
          * "Normal speed" → call control_playback(action: "play", rate: "1.0")
          * "Pause" → call control_playback(action: "pause")
          * "Show me the release" → call control_playback(action: "seek", timestamp: "<release timestamp>")
          * "Ultra slow-mo" → call control_playback(action: "slow_mo", rate: "0.25")
        The bowler's hands are busy — voice is the ONLY way they control playback. Respond instantly.

        PROACTIVE PLAYBACK — YOU CONTROL THE VIDEO:
        You can see the screen. Act on it without being asked:
        - When discussing a specific moment, PAUSE the video and SEEK to that timestamp
        - When showing technique detail, switch to 0.25x slow-mo so the bowler can see it
        - When the bowler asks "show me", immediately seek + slow-mo to the relevant clip timestamp
        - Use "focus_phase" to loop a specific moment: e.g. the front foot landing, the release point
        - After showing something in slow-mo, resume normal speed ("play")
        - Don't ask permission to control playback — just do it, like a coach with a remote

        ANSWERING QUESTIONS:
        The bowler will ask things. Answer like an expert mate, not a chatbot:
        - Use the session data when it's relevant. Quote actual numbers, actual phase results.
        - Use your own bowling knowledge when they ask about technique, famous bowlers, drills, \
        swing physics, pitch conditions. You know bowling deeply — use it.
        - If they ask about something you can show on video, IMMEDIATELY seek to the moment \
        and slow-mo it. Don't just describe — SHOW.
        - If they stray from bowling, gently redirect.
        - If the bowler is quiet, fill the silence: "Let me show you something on this delivery..." \
        and use playback tools to highlight technique points proactively.

        WHAT NOT TO DO:
        - Don't read out data like a report. Form opinions. Say what YOU think.
        - Don't cover every delivery if the bowler just wants highlights.
        - Don't use filler or generic praise. "Nice session" means nothing.
        - Don't repeat the same point in the same words. If they didn't get it, rephrase.
        - Don't fabricate measurements. Use only what the analysis provides.
        - Don't ignore the DNA data — it's one of the most interesting parts. Explain it properly.

        ENDING:
        When the bowler says "done" or "thanks" — give a quick, specific sign-off: top strength, \
        one thing to fix, one drill for next time. Then call `end_session`.
        """
    }

    /// Disconnect the live mate and connect a fresh review agent with all analysis data.
    private func connectReviewAgent() async {
        log.debug("Connecting fresh review agent for post-session walkthrough")

        // Disconnect live mate
        await liveService.disconnect()

        // Small pause for clean teardown
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Set review-specific system prompt
        liveService.systemInstructionOverride = buildReviewAgentPrompt()

        // Connect fresh agent
        do {
            try await liveService.connect()
            matePhase = .postSessionReview
            reviewDeliveryIndex = 0
            log.info("Review agent connected. Deliveries: \(self.session.deliveryCount)")

            // Tell the agent it's connected and can see the results screen.
            // Analysis may still be in progress — let the agent decide how to handle the wait naturally.
            let analyzedCount = session.deliveries.filter { $0.status == .success }.count
            let totalCount = session.deliveryCount
            let clipsReady = session.deliveries.filter { $0.videoURL != nil }.count
            var situationContext = "[REVIEW SESSION CONNECTED] You're now looking at the bowler's results screen. " +
                "\(totalCount) deliveries detected. \(clipsReady) clips extracted."
            if analyzedCount == totalCount && totalCount > 0 {
                situationContext += " All \(totalCount) deliveries have been fully analyzed — data is ready."
            } else if analyzedCount > 0 {
                situationContext += " \(analyzedCount) of \(totalCount) analyzed so far. More analysis arriving."
            } else {
                situationContext += " Analysis is still running — results will arrive as each delivery is processed."
            }
            situationContext += " Continue naturally — no greeting, no re-introduction."
            await liveService.sendContext(situationContext)

            // 10-minute review agent timeout
            startReviewAgentTimeout()
        } catch {
            log.error("Review agent connection failed: \(error.localizedDescription, privacy: .public)")
            matePhase = .idle
        }
    }

    private func startReviewAgentTimeout() {
        reviewAgentTimeoutTask?.cancel()
        reviewAgentTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000) // 10 minutes
            guard let self, !Task.isCancelled, self.matePhase == .postSessionReview else { return }
            log.info("Review agent 10-minute timeout — disconnecting")
            await self.disconnectMate()
        }
    }

    /// Feed a newly completed analysis result to the review agent proactively.
    private func feedAnalysisToReviewAgent(deliveryIndex: Int) async {
        guard matePhase == .postSessionReview, liveService.isConnected else { return }
        let delivery = session.deliveries[deliveryIndex]
        let seq = deliveryIndex + 1

        var parts: [String] = ["[ANALYSIS READY — delivery \(seq) of \(session.deliveryCount)]"]
        if let report = delivery.report, !report.isEmpty {
            parts.append("Summary: \(report)")
        }
        if let kph = delivery.speedKph, let margin = delivery.speedErrorMarginKph {
            parts.append("Estimated speed: \(String(format: "%.0f", kph)) ±\(String(format: "%.0f", margin)) kph (video-based).")
        } else if let kph = delivery.speedKph {
            parts.append("Estimated speed: ~\(String(format: "%.0f", kph)) kph (video-based).")
        }
        if let phases = delivery.phases, !phases.isEmpty {
            for phase in phases {
                var desc = "\(phase.name) [\(phase.status)]: \(phase.observation)"
                if let ts = phase.clipTimestamp {
                    desc += " @ \(String(format: "%.1f", ts))s"
                }
                if !phase.tip.isEmpty {
                    desc += " — Drill: \(phase.tip)"
                }
                parts.append(desc)
            }
        }
        if let matches = delivery.dnaMatches, !matches.isEmpty {
            let top = matches[0]
            parts.append("DNA: \(top.bowlerName) (\(top.country), \(top.era)) \(Int(top.similarityPercent))% similar. Style: \(top.style). Closest phase: \(top.closestPhase). Biggest difference: \(top.biggestDifference). Signature traits: \(top.signatureTraits.joined(separator: "; ")).")
            if matches.count > 1 {
                let others = matches.dropFirst().prefix(2).map { "\($0.bowlerName) \(Int($0.similarityPercent))%" }
                parts.append("Also resembles: \(others.joined(separator: ", ")).")
            }
        }
        if let dna = delivery.dna {
            var traits: [String] = []
            if let ap = dna.armPath { traits.append("arm path: \(ap.rawValue)") }
            if let wp = dna.wristPosition { traits.append("wrist: \(wp.rawValue)") }
            if let ga = dna.gatherAlignment { traits.append("alignment: \(ga.rawValue)") }
            if let rh = dna.releaseHeight { traits.append("release height: \(rh.rawValue)") }
            if let ft = dna.followThroughDirection { traits.append("follow-through: \(ft.rawValue)") }
            if let hs = dna.headStability { traits.append("head: \(hs.rawValue)") }
            if let so = dna.seamOrientation { traits.append("seam: \(so.rawValue)") }
            if !traits.isEmpty {
                parts.append("Action shape: \(traits.joined(separator: ", ")).")
            }
        }
        if let target = challengeTargetBySequence[seq] {
            parts.append("Challenge target: \(target).")
        }

        await liveService.sendContext(parts.joined(separator: " "))

        // Check if ALL deliveries are now analyzed — send full session picture
        let analyzedCount = session.deliveries.filter { $0.status == .success }.count
        if analyzedCount == session.deliveryCount && session.deliveryCount > 0 {
            await sendFullSessionSummaryToReviewAgent()
        }
    }

    /// Send the complete session analysis to the review agent once all deliveries are processed.
    private func sendFullSessionSummaryToReviewAgent() async {
        guard matePhase == .postSessionReview, liveService.isConnected else { return }

        var summary: [String] = ["[ALL \(session.deliveryCount) DELIVERIES ANALYZED — full session data ready]"]

        // Speed trend
        let speeds = session.deliveries.compactMap(\.speedKph)
        if speeds.count >= 2 {
            let first = speeds.prefix(max(speeds.count / 2, 1))
            let second = speeds.suffix(max(speeds.count / 2, 1))
            let avgFirst = first.reduce(0, +) / Double(first.count)
            let avgSecond = second.reduce(0, +) / Double(second.count)
            let trend = avgSecond - avgFirst
            let desc = trend > 2 ? "increasing" : trend < -2 ? "dropping" : "consistent"
            summary.append("Speed trend: \(desc) (first half avg ~\(String(format: "%.0f", avgFirst)), second half avg ~\(String(format: "%.0f", avgSecond)) kph, video-based estimates).")
        }

        // Recurring issues
        let allPhases = session.deliveries.compactMap(\.phases).flatMap { $0 }
        let phaseNames = Set(allPhases.map(\.name))
        for name in phaseNames {
            let needsWork = allPhases.filter { $0.name == name && !$0.isGood }
            if needsWork.count >= 2 {
                let tips = Set(needsWork.compactMap { $0.tip.isEmpty ? nil : $0.tip })
                summary.append("Recurring: \(name) flagged NEEDS WORK \(needsWork.count) times. Drills: \(tips.prefix(2).joined(separator: "; ")).")
            }
        }

        // DNA consistency
        let topMatches = session.deliveries.compactMap(\.dnaMatches?.first)
        if topMatches.count >= 2 {
            let names = topMatches.map(\.bowlerName)
            let unique = Set(names)
            if unique.count == 1, let name = unique.first, let match = topMatches.first {
                summary.append("DNA: Consistently matched \(name) (\(match.country)) across all deliveries at avg \(String(format: "%.0f", topMatches.map(\.similarityPercent).reduce(0, +) / Double(topMatches.count)))%.")
            } else {
                let grouped = Dictionary(grouping: names, by: { $0 }).sorted { $0.value.count > $1.value.count }
                let desc = grouped.prefix(3).map { "\($0.key) ×\($0.value.count)" }.joined(separator: ", ")
                summary.append("DNA variation across session: \(desc).")
            }
        }

        // Challenge score
        if session.mode == .challenge && session.challengeTotal > 0 {
            summary.append("Challenge: \(session.challengeHits)/\(session.challengeTotal) (\(Int(Double(session.challengeHits) / Double(session.challengeTotal) * 100))%).")
        }

        // Best delivery
        let successDeliveries = session.deliveries.filter { $0.status == .success }
        if let best = successDeliveries.max(by: { d1, d2 in
            let score1 = (d1.phases?.filter(\.isGood).count ?? 0)
            let score2 = (d2.phases?.filter(\.isGood).count ?? 0)
            return score1 < score2
        }) {
            let goodPhases = best.phases?.filter(\.isGood).map(\.name).joined(separator: ", ") ?? ""
            summary.append("Best delivery: #\(best.sequence) — \(goodPhases) all good.")
        }

        summary.append("You now have the complete picture. Walk the bowler through the highlights and answer any questions.")
        await liveService.sendContext(summary.joined(separator: " "))
    }

    // MARK: - Auto Stump Calibration

    /// Captures a camera frame after a short delay, sends to Gemini for stump detection.
    /// If both stumps found: locks calibration, enables 120fps, shows corridor.
    /// Called when the mate triggers stump alignment via tool call.
    /// Shows boxes, scans every 3s for up to 20s, locks if found, hides on timeout.
    /// Mate can call again if it fails.
    private func startStumpAlignment() async {
        guard session.isActive else { return }

        // If already locked, don't restart
        if case .locked = calibrationState { return }

        // .detecting already set by the delegate before this task started
        log.info("Stump alignment scanning started")

        // Scan every 1.5s for up to 15 seconds (10 attempts) — fast for demo responsiveness
        let maxAttempts = 10
        for attempt in 1...maxAttempts {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard session.isActive, calibrationState == .detecting else { return }

            guard let snapshot = captureCurrentFrame() else {
                log.warning("Stump scan attempt \(attempt): no frame")
                continue
            }

            do {
                let result = try await stumpDetectionService.detectStumps(
                    image: snapshot,
                    frameWidth: Int(snapshot.size.width * snapshot.scale),
                    frameHeight: Int(snapshot.size.height * snapshot.scale),
                    fps: WBConfig.speedCalibrationFPS
                )

                if let cal = result {
                    session.calibration = cal
                    calibrationState = .locked(cal)
                    cameraService.setSpeedMode(true)
                    showSpeedSetup = true  // show setup overlay — user confirms distance, then monitoring starts
                    log.info("Stump alignment locked at attempt \(attempt)")

                    if liveService.isConnected {
                        let bx = String(format: "%.2f", cal.bowlerStumpCenter.x)
                        let by = String(format: "%.2f", cal.bowlerStumpCenter.y)
                        let sx = String(format: "%.2f", cal.strikerStumpCenter.x)
                        let sy = String(format: "%.2f", cal.strikerStumpCenter.y)
                        await liveService.sendContext(
                            "[CALIBRATION LOCKED] Stumps detected. Corridor overlaid: bowler (\(bx),\(by)) to striker (\(sx),\(sy)). " +
                            "LINE and LENGTH assessment now active. Speed tracking on."
                        )
                    }
                    return
                }
            } catch {
                log.warning("Stump scan attempt \(attempt) error: \(error.localizedDescription)")
            }
        }

        // All attempts exhausted — hide boxes
        calibrationState = .idle
        log.info("Stump alignment timed out after \(maxAttempts) attempts")

        if liveService.isConnected {
            await liveService.sendContext(
                "[CALIBRATION TIMEOUT] Could not detect stumps after 20 seconds. Boxes hidden. " +
                "You can call show_alignment_boxes again if the bowler repositions."
            )
        }
    }

    /// Grab a UIImage from the current camera preview layer.
    private func captureCurrentFrame() -> UIImage? {
        let layer = cameraService.previewLayer
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            layer.render(in: ctx.cgContext)
        }
    }

    // MARK: - Cliff Detection (Real-Time Speed)

    /// Called when user taps "Start Monitoring" after confirming distance.
    func confirmSpeedSetup() {
        showSpeedSetup = false
        if let cal = session.calibration {
            startCliffDetection(calibration: cal)
        }
    }

    /// User tapped a point on the camera view to mark the stumps.
    /// Creates a striker-end ROI around that point and starts cliff detection.
    /// User positioned a box over the stumps. Center + size are normalized (0-1).
    func markStumpsAt(normalizedPoint: CGPoint, normalizedSize: CGSize = CGSize(width: 0.18, height: 0.22)) {
        isMarkingStumps = false
        sessionInstruction = nil

        // Get camera frame dimensions
        let fw = cameraService.previewLayer.bounds.width * UIScreen.main.scale
        let fh = cameraService.previewLayer.bounds.height * UIScreen.main.scale
        guard fw > 0, fh > 0 else {
            log.warning("Cannot mark stumps: invalid frame dimensions (\(fw)x\(fh))")
            return
        }

        let frameW = Int(fw)
        let frameH = Int(fh)

        // Build ROI directly from the user's box (pixel coordinates)
        let roiX = max((normalizedPoint.x - normalizedSize.width / 2), 0) * CGFloat(frameW)
        let roiY = max((normalizedPoint.y - normalizedSize.height / 2), 0) * CGFloat(frameH)
        let roiW = normalizedSize.width * CGFloat(frameW)
        let roiH = normalizedSize.height * CGFloat(frameH)

        cliffROI = CGRect(x: roiX, y: roiY, width: roiW, height: roiH)
        cliffDetector.reset()
        cliffFrameCounter = 0
        cliffPrevGray = nil

        cliffDetector.onStateChange = { [weak self] newState in
            Task { @MainActor [weak self] in
                self?.handleCliffStateChange(newState)
            }
        }

        stumpMonitoringActive = true
        tts.speak("Monitoring")
        let roiDesc = String(describing: cliffROI!)
        log.info("Stumps marked: center=(\(String(format: "%.2f", normalizedPoint.x)),\(String(format: "%.2f", normalizedPoint.y))) ROI=\(roiDesc, privacy: .public)")
    }

    /// Activate cliff detection after calibration locks.
    private func startCliffDetection(calibration: StumpCalibration) {
        let strikerROINorm = calibration.strikerROI
        cliffROI = CGRect(
            x: strikerROINorm.origin.x * CGFloat(calibration.frameWidth),
            y: strikerROINorm.origin.y * CGFloat(calibration.frameHeight),
            width: strikerROINorm.width * CGFloat(calibration.frameWidth),
            height: strikerROINorm.height * CGFloat(calibration.frameHeight)
        )
        cliffDetector.reset()
        cliffFrameCounter = 0
        cliffPrevGray = nil

        cliffDetector.onStateChange = { [weak self] newState in
            Task { @MainActor [weak self] in
                self?.handleCliffStateChange(newState)
            }
        }

        stumpMonitoringActive = true
        tts.speak("Monitoring")
        log.info("Cliff detection started — monitoring striker ROI at (\(String(format: "%.2f", calibration.strikerStumpCenter.x)), \(String(format: "%.2f", calibration.strikerStumpCenter.y)))")
    }

    private func stopCliffDetection() {
        cliffROI = nil
        cliffPrevGray = nil
        cliffDetector.onStateChange = nil
        cliffDetector.reset()
        stumpMonitoringActive = false
        isMarkingStumps = false
    }

    /// Process a single frame for cliff detection. Called every 8th frame from the video callback.
    /// Extracts grayscale ROI, computes energy, feeds to CliffDetector.
    nonisolated private func processCliffFrame(_ sampleBuffer: CMSampleBuffer, roi: CGRect) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Get Y plane (grayscale) from the biplanar YCbCr buffer
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let frameHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let frameWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)

        // Clamp ROI to frame bounds
        let roiMinX = max(Int(roi.minX), 0)
        let roiMaxX = min(Int(roi.maxX), frameWidth)
        let roiMinY = max(Int(roi.minY), 0)
        let roiMaxY = min(Int(roi.maxY), frameHeight)
        let roiW = roiMaxX - roiMinX
        let roiH = roiMaxY - roiMinY
        guard roiW > 0, roiH > 0 else { return }

        // Extract grayscale ROI crop
        let src = baseAddress.assumingMemoryBound(to: UInt8.self)
        var crop = [UInt8](repeating: 0, count: roiW * roiH)
        for y in 0..<roiH {
            let srcRow = src.advanced(by: (roiMinY + y) * bytesPerRow + roiMinX)
            crop.replaceSubrange(y * roiW ..< (y + 1) * roiW,
                                 with: UnsafeBufferPointer(start: srcRow, count: roiW))
        }

        // Compute energy: mean absolute difference from previous frame's ROI
        let energy: Double
        if let prev = cliffPrevGray, prev.count == crop.count {
            var sum: Int = 0
            for i in 0..<crop.count {
                let d = Int(crop[i]) - Int(prev[i])
                sum += d < 0 ? -d : d
            }
            energy = Double(sum) / Double(crop.count)
        } else {
            energy = 0
        }
        cliffPrevGray = crop

        // Feed to cliff detector
        let frameIdx = cliffFrameCounter
        if let detection = cliffDetector.feedEnergy(energy, atFrame: frameIdx) {
            Task { @MainActor in
                self.handleCliffDetection(detection)
            }
        }
    }

    private func handleCliffDetection(_ detection: CliffDetection) {
        log.info("CLIFF DETECTED at frame \(detection.meetFrame), energy=\(detection.meetEnergy), ratio=\(detection.cliffRatio)")
        // Save timestamp for clip extraction later
        let timestamp = Double(detection.meetFrame) / cliffDetector.fps
        cliffTimestamps.append(timestamp)
    }

    private func handleCliffStateChange(_ newState: CliffDetector.State) {
        cliffState = newState
        switch newState {
        case .stumpsHit:
            tts.speak("Well bowled!")
        case .rearranging:
            tts.speak("Fix the stumps")
        case .monitoring:
            tts.speak("Ready")
        }
    }

    static func cameraSwitchContext(for position: AVCaptureDevice.Position) -> String {
        let label = position == .front ? "front" : "back"
        return "Camera switched to \(label) camera. Treat this active camera view as source of truth now and briefly acknowledge the switch."
    }

    private static func formatCandidateTimeline(
        _ candidates: [DeliveryTimestampCandidate],
        limit: Int = 12
    ) -> String {
        guard !candidates.isEmpty else { return "-" }
        let prefix = candidates.prefix(limit).map { candidate in
            String(format: "%.2f@%.2f:%@", candidate.timestamp, candidate.confidence, candidate.source.rawValue)
        }.joined(separator: ", ")
        if candidates.count > limit {
            return "\(prefix), +\(candidates.count - limit) more"
        }
        return prefix
    }

    static func shouldEndSession(from transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(separator: " ").map(String.init)
        let phrases: [[String]] = [
            ["end", "session"],
            ["end", "the", "session"],
            ["end", "this", "session"],
            ["end", "my", "session"],
            ["stop", "session"],
            ["stop", "the", "session"],
            ["stop", "this", "session"],
            ["finish", "session"],
            ["finish", "the", "session"],
            ["finish", "this", "session"],
            ["wrap", "up", "session"],
            ["wrap", "up", "the", "session"],
            ["session", "over"],
            ["that", "ll", "do"],
            ["let", "s", "call", "it"],
            ["i", "m", "done"]
        ]

        return phrases.contains { phrase in
            guard phrase.count <= tokens.count else { return false }
            for index in 0...(tokens.count - phrase.count) {
                if Array(tokens[index..<(index + phrase.count)]) == phrase {
                    return true
                }
            }
            return false
        }
    }
}

private final class RecordingOffsetStore: @unchecked Sendable {
    private let lock = NSLock()
    private var startTime: CMTime?

    func reset() {
        lock.lock()
        startTime = nil
        lock.unlock()
    }

    func markIfNeeded(_ time: CMTime) {
        lock.lock()
        if startTime == nil {
            startTime = time
        }
        lock.unlock()
    }

    func startSeconds() -> Double {
        lock.lock()
        let seconds = CMTimeGetSeconds(startTime ?? .zero)
        lock.unlock()
        return seconds
    }
}

// MARK: - Actor Counter (thread-safe progress tracking)

private actor ActorCounter {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

// MARK: - VoiceMateDelegate

extension SessionViewModel: VoiceMateDelegate {
    nonisolated func voiceMate(didReceiveAudio pcmData: Data) {
        Task { @MainActor in
            liveAudioChunkCounter += 1
            if liveAudioChunkCounter == 1 || liveAudioChunkCounter % 25 == 0 {
                log.debug("Live audio chunk received count=\(self.liveAudioChunkCounter) bytes=\(pcmData.count)")
            }
            AudioSessionManager.shared.playPCMChunk(pcmData)
            isMateSpeaking = true
            tts.mateSpeaking = true
        }
    }

    nonisolated func voiceMate(didTranscribe text: String) {
        Task { @MainActor in
            if !text.isEmpty {
                lastTranscript = text
            }
        }
    }

    nonisolated func voiceMate(didTranscribeUser text: String) {
        Task { @MainActor in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            log.debug("User transcript received: \(text, privacy: .public)")

            if session.isActive && Self.shouldEndSession(from: text) {
                log.debug("End-session intent detected from user transcript")
                await endSession()
                return
            }

            // Review mode voice commands — direct client-side parsing for instant response.
            // The Gemini agent also handles these via tool calls, but client-side is faster.
            if matePhase == .postSessionReview {
                let lower = text.lowercased()
                if lower.contains("next") {
                    let nextIdx = min(reviewDeliveryIndex + 1, session.deliveryCount - 1)
                    await reviewDelivery(at: nextIdx)
                } else if lower.contains("previous") || lower.contains("back") {
                    let prevIdx = max(reviewDeliveryIndex - 1, 0)
                    await reviewDelivery(at: prevIdx)
                } else if lower.contains("done") || lower.contains("that's all") || lower.contains("finish") {
                    await disconnectMate()
                }

                // Direct playback voice commands — instant client-side response.
                // Word boundary matching avoids false positives (e.g. "replay" ≠ "play").
                let words = Set(lower.split(separator: " ").map(String.init))
                if words.contains("pause") || words.contains("freeze") {
                    playbackCommand = PlaybackCommand(action: .pause, timestamp: nil, rate: nil)
                } else if lower.contains("normal speed") || lower.contains("normal rate") || words.contains("1x") {
                    playbackCommand = PlaybackCommand(action: .play, timestamp: nil, rate: 1.0)
                } else if words.contains("play") || words.contains("resume") {
                    playbackCommand = PlaybackCommand(action: .play, timestamp: nil, rate: nil)
                } else if words.contains("slow") || lower.contains("slo-mo") || lower.contains("slow mo") || lower.contains("slow motion") {
                    let rate: Float
                    if lower.contains("0.25") || words.contains("quarter") || words.contains("ultra") {
                        rate = 0.25
                    } else if lower.contains("0.5") || words.contains("half") {
                        rate = 0.5
                    } else {
                        rate = 0.25
                    }
                    playbackCommand = PlaybackCommand(action: .slowMo, timestamp: nil, rate: rate)
                } else if words.contains("fast") || words.contains("2x") || words.contains("double") {
                    playbackCommand = PlaybackCommand(action: .play, timestamp: nil, rate: 2.0)
                }
            }
        }
    }

    nonisolated func voiceMateDidFinishTurn() {
        Task { @MainActor in
            isMateSpeaking = false
            tts.mateSpeaking = false
        }
    }

    nonisolated func voiceMate(didChangeConnectionState connected: Bool) {
        Task { @MainActor in
            if !connected && connectionState == .connected {
                connectionState = .disconnected
            }
        }
    }

    nonisolated func voiceMate(didDisconnect reason: String) {
        Task { @MainActor in
            debugLog += "DISCONNECT: \(reason)\n"

            // Auto-reconnect while session is active OR in review mode
            let shouldReconnect = session.isActive || matePhase == .postSessionReview
            guard shouldReconnect else {
                log.debug("Ignoring disconnect (not active, not reviewing): \(reason, privacy: .public)")
                return
            }

            reconnectAttempts += 1
            let attempt = reconnectAttempts

            // Exponential backoff: 1.5s, 3s, 6s, capped at 15s
            let backoffNs = UInt64(min(1.5 * pow(2.0, Double(attempt - 1)), 15.0) * 1_000_000_000)
            log.debug("Auto-reconnecting (attempt \(attempt)) after disconnect: \(reason, privacy: .public), matePhase=\(String(describing: self.matePhase)), backoff=\(backoffNs / 1_000_000)ms")
            errorMessage = "Reconnecting..."
            debugLog += "Reconnecting (attempt \(attempt))...\n"

            try? await Task.sleep(nanoseconds: backoffNs)

            guard session.isActive || matePhase == .postSessionReview else { return }

            do {
                // In review mode, re-set the review agent system prompt before reconnecting.
                // The systemInstructionOverride is one-shot and gets cleared after connect().
                if matePhase == .postSessionReview {
                    liveService.systemInstructionOverride = buildReviewAgentPrompt()
                }

                try await liveService.connect()
                reconnectAttempts = 0 // Reset on success
                errorMessage = nil
                debugLog += "Reconnected!\n"

                if matePhase == .postSessionReview {
                    // Re-send session context so the review agent knows where we are
                    let analyzedCount = session.deliveries.filter { $0.status == .success }.count
                    let totalCount = session.deliveryCount
                    let currentDelivery = reviewDeliveryIndex + 1
                    await liveService.sendContext(
                        "[RECONNECTED — REVIEW SESSION] You're back. \(totalCount) deliveries, " +
                        "\(analyzedCount) analyzed. Currently looking at delivery \(currentDelivery). " +
                        "The bowler was talking to you — pick up naturally. Don't re-introduce yourself."
                    )
                    log.info("Review agent reconnected with context: delivery \(currentDelivery)/\(totalCount)")
                } else if session.isActive {
                    await maybeSendProactiveGreetingIfNeeded()
                }
            } catch {
                debugLog += "RECONNECT FAIL (attempt \(attempt)): \(error.localizedDescription)\n"
                errorMessage = "Reconnect failed: \(error.localizedDescription)"
            }
        }
    }

    func voiceMate(didRequestEndSession reason: String) async {
        log.debug("Mate requested session end: \(reason, privacy: .public)")
        if session.isActive {
            await endSession()
        } else if matePhase == .postSessionReview {
            await disconnectMate()
        }
    }

    func voiceMate(didRequestNavigateDelivery action: String, deliveryNumber: Int?) async {
        guard matePhase == .postSessionReview else { return }
        log.debug("Mate navigation request: action=\(action, privacy: .public) deliveryNumber=\(deliveryNumber ?? -1)")

        switch action {
        case "next":
            let nextIdx = min(reviewDeliveryIndex + 1, session.deliveryCount - 1)
            await reviewDelivery(at: nextIdx)
        case "previous":
            let prevIdx = max(reviewDeliveryIndex - 1, 0)
            await reviewDelivery(at: prevIdx)
        case "goto":
            if let num = deliveryNumber, num >= 1, num <= session.deliveryCount {
                await reviewDelivery(at: num - 1)
            }
        default:
            break
        }
    }

    func voiceMate(didRequestPlaybackControl action: String, timestamp: Double?, rate: Float?) async {
        log.debug("Mate playback control: action=\(action, privacy: .public) ts=\(timestamp ?? -1) rate=\(rate ?? -1)")

        let playbackAction: PlaybackAction
        switch action {
        case "play": playbackAction = .play
        case "pause": playbackAction = .pause
        case "slow_mo": playbackAction = .slowMo
        case "seek": playbackAction = .seek
        case "focus_phase": playbackAction = .focusPhase
        default: return
        }

        playbackCommand = PlaybackCommand(
            action: playbackAction,
            timestamp: timestamp,
            rate: rate
        )
    }

    func voiceMate(didSetSessionDuration minutes: Int) async {
        let newDuration = TimeInterval(minutes * 60)
        let elapsed = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        self.sessionDurationSeconds = newDuration
        let remaining = max(newDuration - elapsed, 0)
        self.sessionRemainingSeconds = remaining

        log.info("Session duration set to \(minutes) minutes by mate (remaining: \(Int(remaining))s)")

        // Restart timer with new duration
        startSessionTimer()

        // Tell the mate the timer is set
        let remainingMins = Int(remaining / 60)
        if liveService.isConnected {
            await liveService.sendContext("[TIMER SET] Session timer set to \(minutes) minutes. \(remainingMins) minutes remaining. The countdown is visible on screen.")
        }
    }

    func voiceMateDidRequestShowAlignmentBoxes() async {
        guard session.isActive, WBConfig.enableSpeedCalibration else { return }
        // Show boxes immediately, run scan in background so tool response isn't delayed
        calibrationState = .detecting
        Task { await self.startStumpAlignment() }
    }

    func voiceMate(didSetChallengeTarget target: String) async {
        guard session.isActive else { return }

        // Switch to challenge mode if not already
        if session.mode != .challenge {
            session.mode = .challenge
            log.info("Challenge mode activated by mate")
        }

        session.currentChallenge = target
        currentChallengeTarget = target
        log.info("Challenge target set by mate: \(target, privacy: .public)")

        if liveService.isConnected {
            await liveService.sendContext("[CHALLENGE ACTIVE] Target: \"\(target)\". The bowler can see this on screen. The next delivery will be evaluated against it.")
        }
    }

}

// MARK: - DeliveryDetectionDelegate

extension SessionViewModel: DeliveryDetectionDelegate {
    nonisolated func didDetectDelivery(
        at timestamp: Double,
        bowlingArm: BowlingArm,
        paceBand: PaceBand,
        wristOmega: Double,
        releaseWristY: Double?
    ) {
        // MediaPipe detection is disabled — Gemini Flash segment scanner is the sole
        // source of truth for deliveries. This delegate method is retained only to
        // satisfy the DeliveryDetectionDelegate protocol conformance.
    }
}

// MARK: - Live Segment Detection Queues

extension SessionViewModel {

    /// Start the two-queue live detection system.
    /// Queue A: 30s segments → Gemini Flash detection (serial)
    /// Queue B: 5s clips → deep analysis (serial)
    /// Both run concurrently.
    func startLiveSegmentDetection() {
        liveScannedUpTo = 0
        liveDetectedTimestamps = []
        liveDetectionQueue = []
        liveDeepAnalysisQueue = []

        // Start Queue A processor
        liveDetectionTask = Task { [weak self] in
            await self?.processDetectionQueue()
        }

        // Start Queue B processor
        liveDeepAnalysisTask = Task { [weak self] in
            await self?.processDeepAnalysisQueue()
        }

        // Start segment production timer
        let segmentDuration = WBConfig.liveSegmentDurationSeconds
        let segmentOverlap = WBConfig.liveSegmentOverlapSeconds
        let segmentStride = max(segmentDuration - segmentOverlap, 10.0)
        liveSegmentTimerTask = Task { [weak self] in
            // Wait for first full segment to accumulate
            try? await Task.sleep(nanoseconds: UInt64(segmentDuration * 1_000_000_000))

            while !Task.isCancelled {
                guard let self, self.session.isActive else { break }
                guard let recordingURL = self.cameraService.currentRecordingURL else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }

                let recordingOffset = self.recordingOffsetStore.startSeconds()
                let currentRecordingTime = Date().timeIntervalSince(self.sessionStartTime ?? Date())
                let segmentEnd = max(currentRecordingTime - recordingOffset, 0)
                // Step back by overlap to catch deliveries at segment boundaries
                let segmentStart = max(segmentEnd - segmentDuration, 0)
                let duration = segmentEnd - segmentStart

                guard duration >= 5.0 else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }

                do {
                    let segmentURL = try await self.exportDetectionSegment(
                        from: recordingURL,
                        startTime: segmentStart,
                        duration: duration
                    )
                    self.liveDetectionQueue.append((url: segmentURL, startTime: segmentStart))
                    log.debug("Live segment queued: [\(String(format: "%.1f", segmentStart))s-\(String(format: "%.1f", segmentEnd))s] (\(String(format: "%.1f", duration))s)")
                } catch {
                    log.error("Live segment export failed: \(error.localizedDescription, privacy: .public)")
                }

                // Wait for next stride (segment minus overlap)
                try? await Task.sleep(nanoseconds: UInt64(segmentStride * 1_000_000_000))
            }
        }

        log.debug("Live segment detection started: \(segmentDuration)s segments, \(segmentOverlap)s overlap, stride \(segmentStride)s, confidence threshold \(WBConfig.liveSegmentConfidenceThreshold)")
    }

    /// Stop all live detection queues and clean up.
    func stopLiveSegmentDetection() {
        liveSegmentTimerTask?.cancel()
        liveSegmentTimerTask = nil
        liveDetectionTask?.cancel()
        liveDetectionTask = nil
        liveDeepAnalysisTask?.cancel()
        liveDeepAnalysisTask = nil

        // Clean up queued segment files
        for entry in liveDetectionQueue {
            try? FileManager.default.removeItem(at: entry.url)
        }
        liveDetectionQueue = []
        liveDeepAnalysisQueue = []
        liveDetectedTimestamps = []

        log.debug("Live segment detection stopped")
    }

    /// Queue A processor: detect deliveries in segments serially.
    private func processDetectionQueue() async {
        while !Task.isCancelled {
            guard let entry = liveDetectionQueue.first else {
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms poll
                continue
            }
            liveDetectionQueue.removeFirst()
            let segmentURL = entry.url
            let segmentStartTime = entry.startTime
            defer { try? FileManager.default.removeItem(at: segmentURL) }

            guard session.isActive else { break }

            do {
                let asset = AVURLAsset(url: segmentURL)
                let segmentDuration = try await asset.load(.duration).seconds

                let detections = try await analysisService.detectDeliveryTimestampsInSegment(
                    segmentURL: segmentURL,
                    segmentDuration: segmentDuration
                )

                for detection in detections {
                    guard detection.confidence >= WBConfig.liveSegmentConfidenceThreshold else {
                        log.debug("Live detection skipped: confidence \(String(format: "%.2f", detection.confidence)) < \(WBConfig.liveSegmentConfidenceThreshold)")
                        continue
                    }

                    // Global timestamp = segment start in recording + local detection offset
                    let globalTimestamp = segmentStartTime + detection.localTimestamp
                    let isDuplicate = liveDetectedTimestamps.contains { abs($0 - globalTimestamp) < WBConfig.liveDedupeWindowSeconds }
                    if isDuplicate {
                        log.debug("Live detection deduplicated at \(String(format: "%.1f", globalTimestamp))s")
                        continue
                    }

                    liveDetectedTimestamps.append(globalTimestamp)

                    // Extract 5s clip (extractClip handles preRoll/postRoll internally)
                    guard let recordingURL = cameraService.currentRecordingURL else { continue }

                    do {
                        let clipURL = try await clipExtractor.extractClip(
                            from: recordingURL,
                            at: globalTimestamp,
                            preRoll: WBConfig.clipPreRoll,
                            postRoll: WBConfig.clipPostRoll
                        )

                        // Create delivery — wristOmega/releaseWristY are nil because
                        // MediaPipe's didDetectDelivery is silenced (Gemini Flash is sole
                        // detector). DNA extraction handles nil gracefully via sentinel values.
                        let count = session.deliveryCount + 1
                        let delivery = Delivery(
                            timestamp: globalTimestamp,
                            status: .queued,
                            sequence: count
                        )
                        session.addDelivery(delivery)
                        session.deliveries[count - 1].videoURL = clipURL
                        session.deliveries[count - 1].thumbnail = ClipThumbnailGenerator.releaseThumbnail(
                            from: clipURL,
                            releaseOffset: WBConfig.clipPreRoll
                        )
                        deepAnalysisStatusByDelivery[delivery.id] = DeliveryDeepAnalysisStatus(
                            stage: .idle, elapsedSeconds: 0, statusMessage: "", failureMessage: nil
                        )

                        // Record current challenge target for this delivery
                        if session.mode == .challenge, let target = session.currentChallenge {
                            challengeTargetBySequence[count] = target
                        }

                        log.debug("Live delivery detected: D\(count) at \(String(format: "%.1f", globalTimestamp))s, confidence \(String(format: "%.2f", detection.confidence))")

                        // TTS announce
                        tts.speak("\(count).")

                        // Notify buddy
                        if liveService.isConnected {
                            await liveService.sendContext("[DELIVERY \(count) detected at \(String(format: "%.1f", globalTimestamp))s] Confidence: \(String(format: "%.0f", detection.confidence * 100))%. Clip ready — queued for deep analysis.")
                        }

                        // Enqueue for deep analysis
                        liveDeepAnalysisQueue.append(delivery.id)

                    } catch {
                        log.error("Live clip extraction failed at \(String(format: "%.1f", globalTimestamp))s: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                log.error("Live segment detection failed: \(error.localizedDescription, privacy: .public)")
                if liveService.isConnected {
                    await liveService.sendContext("[DETECTION TIMEOUT] A detection segment timed out. Don't worry — continuing to scan for deliveries.")
                }
            }
        }
    }

    /// Queue B processor: deep analysis serially.
    private func processDeepAnalysisQueue() async {
        while !Task.isCancelled {
            guard !liveDeepAnalysisQueue.isEmpty else {
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms poll
                continue
            }

            let deliveryID = liveDeepAnalysisQueue.removeFirst()
            guard session.isActive else { break }

            await runDeepAnalysis(for: deliveryID)
        }
    }
}
