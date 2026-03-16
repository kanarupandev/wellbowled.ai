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
        case liveBowling                // Active session — coaching in real time
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
    @Published var sessionRemainingSeconds: TimeInterval = WBConfig.liveSessionMaxDurationSeconds
    @Published var currentChallengeTarget: String?
    @Published var isPreparingClips: Bool = false
    @Published var clipPreparationProgress: Double = 0
    @Published private(set) var clipPreparationStatusMessage: String = ""
    @Published private(set) var deepAnalysisStatusByDelivery: [UUID: DeliveryDeepAnalysisStatus] = [:]
    @Published private(set) var deepAnalysisArtifactsByDelivery: [UUID: DeliveryDeepAnalysisArtifacts] = [:]
    @Published private(set) var lastSessionRecordingURL: URL?
    @Published private(set) var sessionVideoSaveStatus: SessionVideoSaveStatus = .idle
    @Published private(set) var cameraFlipDisabled: Bool = false

    // Persistent voice mate state
    @Published private(set) var matePhase: MatePhase = .idle
    @Published var reviewDeliveryIndex: Int = 0

    // MARK: - Services

    let cameraService = CameraService()
    private let liveService = GeminiLiveService()
    private let audioManager = AudioSessionManager.shared
    private let detector = DeliveryDetector(fps: 30.0)
    private let tts = TTSService()
    private let clipExtractor = ClipExtractor()
    private let analysisService = GeminiAnalysisService()
    private let clipPoseExtractor = ClipPoseExtractor()

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

    // Live segment detection queues
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
        cameraFlipDisabled = false
        challengeTargetBySequence = [:]
        challengeEngine.reset(shuffle: true)
        session.currentChallenge = nil
        currentChallengeTarget = nil
        shouldSendProactiveGreeting = true
        didSendProactiveGreeting = false
        flowPhase = .starting
        sessionStartTime = nil
        sessionRemainingSeconds = WBConfig.liveSessionMaxDurationSeconds
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
        startSessionTimer()

        // 1. Configure audio session
        do {
            audioManager.stopPlaybackEngine()
            try audioManager.configure()
            try audioManager.startPlaybackEngine()
            let liveService = self.liveService
            useCameraAudioFallback = !audioManager.startLiveInputCapture { pcmData in
                liveService.sendAudio(pcmData)
            }
            if useCameraAudioFallback {
                log.warning("Primary audio tap unavailable; using camera audio fallback")
            } else {
                log.debug("Primary live mic uplink using AudioSession tap")
            }
            log.debug("Audio configured")
            let routeSummary = audioManager.currentRouteSummary()
            debugLog += "Audio route: \(routeSummary)\n"
            log.debug("Audio route after configure: \(routeSummary, privacy: .public)")
        } catch {
            rollbackSessionStartFailure(reason: "Audio setup failed: \(error.localizedDescription)")
            return
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

        // 3b. Start live segment detection queues
        if WBConfig.enableLiveAutoAnalysis {
            startLiveSegmentDetection()
        }

        // 4. Start delivery detection
        detector.start()
        log.debug("Delivery detection started")

        // 5. Wire camera outputs
        wireCameraOutputs()
        log.debug("Camera outputs wired")

        // 6. Connect to Gemini Live API
        do {
            debugLog += "Connecting...\n"
            debugLog += "Key: \(WBConfig.hasAPIKey ? "YES" : "NO")\n"
            try await liveService.connect()
            debugLog += "Connected!\n"
            matePhase = .liveBowling
            await maybeSendProactiveGreetingIfNeeded()
        } catch {
            debugLog += "FAIL: \(error.localizedDescription)\n"
            errorMessage = "Connection failed: \(error.localizedDescription)"
            // Session continues — detection + TTS still work without Live API
        }
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

        // Stop detection
        detector.stop()
        tts.stop()
        stopLiveSegmentDetection()

        // KEEP Live API connected — transition to review mode instead of disconnecting.
        // The mate stays on to walk through analysis results with the bowler.
        if liveService.isConnected {
            matePhase = .postSessionReview
            reviewDeliveryIndex = 0
            let deliveryCount = session.deliveryCount
            await liveService.sendContext("""
            [SESSION ENDED — REVIEW MODE] The bowling session is over. \(deliveryCount) deliveries bowled. \
            You are now in review mode. Stay connected — you will receive analysis results as they complete. \
            Walk the bowler through each delivery's analysis naturally. \
            Summarize the session briefly first, then wait for results to come in. \
            The bowler can say "next" or "previous" to navigate deliveries, or ask about specific aspects. \
            When the bowler says "done" or "that's all", wrap up with a final summary.
            """)
            log.debug("Mate transitioned to post-session review mode")
        } else {
            matePhase = .idle
        }

        // Stop recording + camera (but keep audio alive for voice mate)
        cameraService.stopRecording()
        cameraService.stopSession()

        // End session
        session.end()
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
        detector.stop()
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
        clipPreparationStatusMessage = "Scanning uploaded recording for deliveries..."
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
        startClipPreparation(recordingURL: recordingURL)
    }

    /// Fully disconnect the voice mate. Called when the user exits to home.
    /// This tears down the Live API WebSocket and audio session.
    func disconnectMate() async {
        log.debug("Disconnecting mate (full teardown)")
        await liveService.disconnect()
        audioManager.stopLiveInputCapture()
        audioManager.stopPlaybackEngine()
        audioManager.deactivateSession()
        matePhase = .idle
        lastTranscript = ""
        isMateSpeaking = false
    }

    /// Navigate to a specific delivery in review mode and tell the mate.
    func reviewDelivery(at index: Int) async {
        guard matePhase == .postSessionReview else { return }
        guard index >= 0, index < session.deliveryCount else { return }
        reviewDeliveryIndex = index
        let delivery = session.deliveries[index]
        let seq = index + 1

        var context = "[REVIEWING DELIVERY \(seq)] The bowler is now looking at delivery \(seq)."
        if let phases = delivery.phases, !phases.isEmpty {
            let good = phases.filter(\.isGood).map(\.name).joined(separator: ", ")
            let work = phases.filter { !$0.isGood }.map(\.name).joined(separator: ", ")
            context += " Phases — Good: \(good.isEmpty ? "none" : good). Needs work: \(work.isEmpty ? "none" : work)."
        }
        if let speedKph = delivery.speedKph {
            context += " Speed: \(String(format: "%.1f", speedKph)) kph."
        }
        if let report = delivery.report {
            context += " Report: \(report)"
        }

        if liveService.isConnected {
            await liveService.sendContext(context)
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
                print("[ClipDebug] Flip wait attempt \(attempt): \(segs.count) segments")
                if segs.count > 1 {
                    let lastSeg = segs.last!
                    print("[ClipDebug] Using LAST segment: \(lastSeg.lastPathComponent)")
                    log.info("Camera was flipped; using last segment: \(lastSeg.lastPathComponent, privacy: .public)")
                    return lastSeg
                }
            }
            // Fallback: use the currentRecordingURL (front camera file path, may still be finalizing)
            if let fb = fallback, FileManager.default.fileExists(atPath: fb.path) {
                print("[ClipDebug] Flip fallback to currentRecordingURL: \(fb.lastPathComponent)")
                log.warning("Camera flip: second segment not found in recordedSegmentURLs; using fallback")
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
        detector.stop()
        tts.stop()
        audioManager.stopPlaybackEngine()
        audioManager.stopLiveInputCapture()
        cameraService.stopRecording()
        cameraService.stopSession()

        session.end()
        session.deliveries.removeAll()
        sessionRemainingSeconds = WBConfig.liveSessionMaxDurationSeconds
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
                let remaining = max(WBConfig.liveSessionMaxDurationSeconds - elapsed, 0)
                self.sessionRemainingSeconds = remaining

                if remaining <= 0 {
                    let minutes = Int((WBConfig.liveSessionMaxDurationSeconds / 60).rounded())
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

        // Video frames → MediaPipe detection + Live API
        let ciCtx = self.ciContext  // capture to avoid accessing MainActor self from bg
        cameraService.onVideoFrame = { [weak self] sampleBuffer, timestamp in
            guard let self else { return }

            // Track recording start time for clip extraction offset
            self.recordingOffsetStore.markIfNeeded(timestamp)

            // Feed MediaPipe detector (thread-safe: processFrame is designed for bg calls)
            self.detector.processFrame(sampleBuffer, at: timestamp)

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
        print("[ClipDebug] recordingOffset=\(recordingOffset), recordingURL=\(recordingURL.lastPathComponent)")
        print("[ClipDebug] deliveries=\(session.deliveries.map { "ts=\($0.timestamp)" })")
        let recordingAsset = AVURLAsset(url: recordingURL)
        let recordingDurationTime = (try? await recordingAsset.load(.duration)) ?? .zero
        let recordingDuration = max(CMTimeGetSeconds(recordingDurationTime), 0)

        // Skip post-session Gemini segment scan if live scanning already found deliveries
        let liveFoundDeliveries = session.deliveries.contains { $0.videoURL != nil }
        if liveFoundDeliveries {
            log.info("Post-session scan skipped: live segment detection already found \(self.session.deliveryCount) deliveries with clips")
            clipPreparationProgress = 0.5
        } else {
            let batchCandidates = await detectDeliveryCandidatesWithGemini(
                recordingURL: recordingURL,
                recordingDuration: recordingDuration,
                sourceSessionStart: sourceSessionStart
            )
            if Task.isCancelled || session.startedAt != sourceSessionStart {
                log.debug("Clip preparation stopped after segment scan: task cancelled or session changed")
                isPreparingClips = false
                return
            }

            clipPreparationStatusMessage = "Merging live and batch detections..."
            clipPreparationProgress = 0.5
            rebuildDeliveriesFromDetectionCandidates(
                batchCandidates: batchCandidates,
                recordingOffset: recordingOffset,
                recordingDuration: recordingDuration
            )
        }

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
            print("🦴 [Artifacts] MISS for \(deliveryID.uuidString.prefix(8)). Available: \(deepAnalysisArtifactsByDelivery.keys.map { String($0.uuidString.prefix(8)) })")
        }
        return result
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
        case dna(Result<BowlingDNA, Error>)
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
            group.addTask { [analysisService] in
                do {
                    let deep = try await analysisService.analyzeDeliveryDeep(clipURL: clipURL)
                    return .detailed(.success(deep))
                } catch {
                    return .detailed(.failure(error))
                }
            }

            group.addTask { [analysisService, delivery = self.session.deliveries[index]] in
                do {
                    let dna = try await analysisService.extractBowlingDNA(
                        clipURL: clipURL,
                        wristOmega: delivery.wristOmega,
                        releaseWristY: delivery.releaseWristY
                    )
                    return .dna(.success(dna))
                } catch {
                    return .dna(.failure(error))
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
                    log.debug("Deep analysis component ready: detailed delivery=\(index + 1)")
                case .detailed(.failure(let error)):
                    log.error("Deep analysis failed for D\(index + 1): \(error.localizedDescription)")
                case .dna(.success(let dna)):
                    dnaResult = dna
                    log.debug("Deep analysis component ready: dna delivery=\(index + 1)")
                case .dna(.failure(let error)):
                    log.debug("DNA extraction failed for D\(index + 1): \(error.localizedDescription, privacy: .public)")
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

        if let dna = dnaResult {
            session.deliveries[index].dna = dna
            session.deliveries[index].dnaMatches = BowlingDNAMatcher.match(userDNA: dna)
        }

        var artifacts = deepAnalysisArtifactsByDelivery[deliveryID] ?? DeliveryDeepAnalysisArtifacts()
        artifacts.poseFrames = poseFrames
        if poseFrames.isEmpty {
            artifacts.poseFailureReason = poseFailureReason ?? "No confident pose landmarks detected in the delivery clip. Try closer framing and stronger lighting."
            print("🦴 [DeepAnalysis] Pose FAILED for D\(index + 1): \(artifacts.poseFailureReason!)")
        } else {
            artifacts.poseFailureReason = nil
            print("🦴 [DeepAnalysis] Pose SUCCESS for D\(index + 1): \(poseFrames.count) frames")
        }
        artifacts.expertAnalysis = detailedResult.expertAnalysis ?? ExpertAnalysisBuilder.build(from: detailedResult.phases)
        deepAnalysisArtifactsByDelivery[deliveryID] = artifacts
        print("🦴 [DeepAnalysis] Stored artifacts for deliveryID=\(deliveryID.uuidString.prefix(8)), poseFrames=\(poseFrames.count), poseFailure=\(poseFailureReason ?? "none")")

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
            if !detailedResult.paceEstimate.isEmpty {
                feedbackParts.append("Pace: \(detailedResult.paceEstimate)")
            }
            let goodPhases = detailedResult.phases.filter { $0.isGood }.map(\.name)
            let needsWorkPhases = detailedResult.phases.filter { !$0.isGood }.map(\.name)
            if !goodPhases.isEmpty {
                feedbackParts.append("Good phases: \(goodPhases.joined(separator: ", "))")
            }
            if !needsWorkPhases.isEmpty {
                feedbackParts.append("Needs work: \(needsWorkPhases.joined(separator: ", "))")
            }
            if let match = session.deliveries[index].dnaMatches?.first {
                feedbackParts.append("DNA match: \(match.bowlerName) (\(match.country)) at \(match.similarityPercent)%. Closest phase: \(match.closestPhase). Biggest difference: \(match.biggestDifference).")
            }
            if let challengeText {
                feedbackParts.append("Challenge result: \(challengeText)")
            }
            feedbackParts.append("Give the bowler a natural spoken debrief — what was good, what needs work, one actionable fix for next ball.")
            await liveService.sendContext(feedbackParts.joined(separator: " "))
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
        [SESSION STARTED] The bowler just opened the app and is at the nets. \
        Greet them naturally and start the conversation. \
        Ask what they want to work on and how long they have. \
        Check you can see their full action in the video feed.
        """)
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

            // Review mode voice navigation
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

            guard session.isActive else {
                // Session already ended: do not surface raw transport errors in UI.
                log.debug("Ignoring disconnect after session end: \(reason, privacy: .public)")
                return
            }

            // Auto-reconnect while session is active or in review mode
            let shouldReconnect = session.isActive || matePhase == .postSessionReview
            guard shouldReconnect else { return }

            errorMessage = "Reconnecting..."
            debugLog += "Reconnecting...\n"

            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s backoff

            guard session.isActive || matePhase == .postSessionReview else { return }

            do {
                try await liveService.connect()
                errorMessage = nil
                debugLog += "Reconnected!\n"
                await maybeSendProactiveGreetingIfNeeded()
            } catch {
                debugLog += "RECONNECT FAIL: \(error.localizedDescription)\n"
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
        Task { @MainActor in
            // When live segment detection is active, MediaPipe is fully silent —
            // Gemini Flash segment scanner is the sole source of truth for deliveries.
            // MediaPipe has too many false positives to notify the buddy.
            if WBConfig.enableLiveAutoAnalysis {
                log.debug("MediaPipe spike at \(timestamp)s — ignored (Gemini Flash is sole detector)")
                return
            }

            // Fallback: when live segment detection is disabled, MediaPipe creates deliveries
            let count = session.deliveryCount + 1
            var challengeTarget: String?
            if session.mode == .challenge {
                challengeTarget = session.currentChallenge
                if let target = challengeTarget {
                    challengeTargetBySequence[count] = target
                }
            }

            let delivery = Delivery(
                timestamp: timestamp,
                status: .clipping,
                sequence: count,
                wristOmega: wristOmega,
                releaseWristY: releaseWristY
            )
            session.addDelivery(delivery)
            deepAnalysisStatusByDelivery[delivery.id] = DeliveryDeepAnalysisStatus(
                stage: .idle,
                elapsedSeconds: 0,
                statusMessage: "",
                failureMessage: nil
            )

            log.debug("Delivery #\(count) detected at \(timestamp)s (\(bowlingArm.rawValue, privacy: .public) arm, \(paceBand.label, privacy: .public))")
            tts.speak("\(count).")
            flowPhase = .active

            if liveService.isConnected {
                let elapsed = Int(Date().timeIntervalSince(sessionStartTime ?? Date()))
                let remaining = max(0, Int(WBConfig.liveSessionMaxDurationSeconds) - elapsed)
                var context = "[DELIVERY \(count) detected] Bowling arm: \(bowlingArm.rawValue). " +
                    "Pace band: \(paceBand.label). Session time: \(elapsed)s elapsed, ~\(remaining)s remaining."
                if let challengeTarget {
                    context += " Active challenge: \(challengeTarget)."
                }
                await liveService.sendContext(context)
            }

            if session.mode == .challenge {
                await issueNextChallengeTarget()
            }
        }
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
            guard !liveDetectionQueue.isEmpty else {
                // Poll for new segments
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let entry = liveDetectionQueue.removeFirst()
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

                        // Create delivery
                        let count = session.deliveryCount + 1
                        let delivery = Delivery(
                            timestamp: globalTimestamp,
                            status: .queued,
                            sequence: count,
                            wristOmega: nil,
                            releaseWristY: nil
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
            }
        }
    }

    /// Queue B processor: deep analysis serially.
    private func processDeepAnalysisQueue() async {
        while !Task.isCancelled {
            guard !liveDeepAnalysisQueue.isEmpty else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let deliveryID = liveDeepAnalysisQueue.removeFirst()
            guard session.isActive else { break }

            await runDeepAnalysis(for: deliveryID)
        }
    }
}
