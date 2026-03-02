import AVFoundation
import Combine
import os
import SwiftUI
import UIKit

private let log = Logger(subsystem: "com.wellbowled", category: "SessionVM")

/// Full session ViewModel: Live API voice + MediaPipe detection + TTS + recording + analysis.
/// Pipeline: Camera → (MediaPipe detection + Live API voice) → TTS count → clip extraction → Gemini analysis
@MainActor
final class SessionViewModel: ObservableObject {

    private enum LiveFlowPhase {
        case greeting
        case planning
        case pilotRun
        case active
    }

    // MARK: - Published State

    @Published var connectionState: LiveConnectionState = .disconnected
    @Published var lastTranscript: String = ""
    @Published var isMateSpeaking: Bool = false
    @Published var errorMessage: String?
    @Published var debugLog: String = ""

    // Session state
    @Published var session = Session()
    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0
    @Published var sessionRemainingSeconds: TimeInterval = WBConfig.liveSessionMaxDurationSeconds
    @Published var currentChallengeTarget: String?

    // MARK: - Services

    let cameraService = CameraService()
    private let liveService = GeminiLiveService()
    private let audioManager = AudioSessionManager.shared
    private let detector = DeliveryDetector(fps: 30.0)
    private let tts = TTSService()
    private let clipExtractor = ClipExtractor()
    private let analysisService = GeminiAnalysisService()

    private var cancellables = Set<AnyCancellable>()
    private let ciContext = CIContext()  // Reuse — creating per frame is expensive
    private var recordingStartTime: CMTime?  // Track recording start for clip offset
    private var sessionTimerTask: Task<Void, Never>?
    private var isEndingSession = false
    private var challengeEngine = ChallengeEngine(targets: WBConfig.challengeTargets, shuffle: true)
    private var challengeTargetBySequence: [Int: String] = [:]
    private var shouldSendProactiveGreeting = false
    private var didSendProactiveGreeting = false
    private var flowPhase: LiveFlowPhase = .greeting
    private var hasBowlerPlanResponse = false
    private var proactiveRepromptTask: Task<Void, Never>?
    private var hasPilotRun = false

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

    func startSession(mode: SessionMode = .freePlay) async {
        log.debug("Starting session...")
        errorMessage = nil
        session.start(mode: mode)
        challengeTargetBySequence = [:]
        currentChallengeTarget = nil
        challengeEngine.reset(shuffle: true)
        shouldSendProactiveGreeting = true
        didSendProactiveGreeting = false
        flowPhase = .greeting
        hasBowlerPlanResponse = false
        hasPilotRun = false
        proactiveRepromptTask?.cancel()
        proactiveRepromptTask = nil
        sessionRemainingSeconds = WBConfig.liveSessionMaxDurationSeconds
        startSessionTimer()
        UIApplication.shared.isIdleTimerDisabled = true

        // 1. Configure audio session
        do {
            try audioManager.configure()
            try audioManager.startPlaybackEngine()
            log.debug("Audio configured")
        } catch {
            log.error("Audio setup failed: \(error.localizedDescription)")
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
            return
        }

        // 2. Start camera
        await cameraService.startSession()
        log.debug("Camera started")

        // 3. Start recording (for post-session clip extraction)
        do {
            try cameraService.startRecording()
            log.debug("Recording started")
        } catch {
            log.warning("Recording start failed: \(error.localizedDescription) — session continues without clip extraction")
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

        // Save recording URL before stopping
        let recordingURL = cameraService.currentRecordingURL

        // Unwire camera
        cameraService.onVideoFrame = nil
        cameraService.onAudioSample = nil

        // Stop detection
        detector.stop()
        tts.stop()

        // Disconnect Live API
        await liveService.disconnect()

        // Stop audio playback
        audioManager.stopPlaybackEngine()

        // Stop recording + camera
        cameraService.stopRecording()
        cameraService.stopSession()

        // End session
        session.end()
        sessionRemainingSeconds = 0
        UIApplication.shared.isIdleTimerDisabled = false
        lastTranscript = ""
        isMateSpeaking = false
        errorMessage = nil
        shouldSendProactiveGreeting = false
        didSendProactiveGreeting = false
        proactiveRepromptTask?.cancel()
        proactiveRepromptTask = nil
        flowPhase = .greeting
        hasBowlerPlanResponse = false
        hasPilotRun = false
        log.debug("Session ended. Deliveries: \(self.session.deliveryCount)")

        // Post-session: extract clips and analyze
        if let url = recordingURL, session.deliveryCount > 0 {
            await runPostSessionAnalysis(recordingURL: url)
        }
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        let startedAt = session.startedAt ?? Date()

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
        cameraService.toggleCamera { [weak self] newPosition in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCameraSwitched(to: newPosition)
            }
        }
    }

    private func handleCameraSwitched(to position: AVCaptureDevice.Position) async {
        guard session.isActive, liveService.isConnected else { return }
        await liveService.sendContext(Self.cameraSwitchContext(for: position))
    }

    private func wireCameraOutputs() {
        // Capture first frame timestamp so delivery timestamps can be offset to recording-relative
        recordingStartTime = nil

        // Video frames → MediaPipe detection + Live API
        let ciCtx = self.ciContext  // capture to avoid accessing MainActor self from bg
        cameraService.onVideoFrame = { [weak self] sampleBuffer, timestamp in
            guard let self else { return }

            // Track recording start time for clip extraction offset
            if self.recordingStartTime == nil {
                self.recordingStartTime = timestamp
            }

            // Feed MediaPipe detector (thread-safe: processFrame is designed for bg calls)
            self.detector.processFrame(sampleBuffer, at: timestamp)

            // Feed Live API — reuse CIContext (creating per frame is ~10ms overhead)
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImage = UIImage(cgImage: cgImage)
            guard let jpegData = uiImage.jpegData(compressionQuality: CGFloat(WBConfig.liveAPIJPEGQuality) / 100.0) else { return }
            self.liveService.sendVideoFrame(jpegData)
        }

        // Audio samples → Live API
        cameraService.onAudioSample = { [weak self] sampleBuffer in
            guard let self else { return }
            guard let pcmData = AudioSessionManager.resampleToLiveAPI(sampleBuffer) else { return }
            self.liveService.sendAudio(pcmData)
        }
    }

    // MARK: - Post-Session Analysis

    private func runPostSessionAnalysis(recordingURL: URL) async {
        guard !session.deliveries.isEmpty else { return }
        log.info("Starting post-session analysis for \(self.session.deliveryCount) deliveries")
        isAnalyzing = true
        analysisProgress = 0

        let total = Double(session.deliveries.count)
        let recordingOffset = CMTimeGetSeconds(recordingStartTime ?? .zero)

        // Phase 1: Extract all clips in parallel (fast, local I/O)
        await withTaskGroup(of: (Int, URL?, Error?).self) { group in
            for (index, delivery) in session.deliveries.enumerated() {
                group.addTask { [clipExtractor] in
                    let clipTimestamp = max(delivery.timestamp - recordingOffset, 0)
                    do {
                        let url = try await clipExtractor.extractClip(from: recordingURL, at: clipTimestamp)
                        return (index, url, nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }
            for await (index, clipURL, error) in group {
                if let clipURL {
                    session.deliveries[index].videoURL = clipURL
                    session.deliveries[index].status = .analyzing
                } else {
                    log.error("D\(index + 1) clip extraction failed: \(error?.localizedDescription ?? "unknown")")
                    session.deliveries[index].status = .failed
                }
            }
        }

        // Phase 2: Analyze all clips in parallel (Gemini API calls)
        let analysisCount = ActorCounter()
        await withTaskGroup(of: (Int, DeliveryAnalysis?, Error?).self) { group in
            for (index, delivery) in session.deliveries.enumerated() {
                guard delivery.status == .analyzing, let clipURL = delivery.videoURL else { continue }
                group.addTask { [analysisService] in
                    do {
                        let analysis = try await analysisService.analyzeDelivery(clipURL: clipURL)
                        return (index, analysis, nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }
            for await (index, analysis, error) in group {
                if let analysis {
                    session.deliveries[index].report = analysis.observation
                    session.deliveries[index].speed = analysis.paceEstimate
                    session.deliveries[index].status = .success
                    log.debug("D\(index + 1) analyzed: \(analysis.paceEstimate), \(analysis.length.rawValue)")
                } else {
                    log.error("D\(index + 1) analysis failed: \(error?.localizedDescription ?? "unknown")")
                    session.deliveries[index].status = .failed
                }
                let completed = await analysisCount.increment()
                analysisProgress = Double(completed) / total
            }
        }

        // Phase 2b: Challenge mode evaluation (target hit/miss per delivery)
        if session.mode == .challenge {
            await withTaskGroup(of: (Int, String, ChallengeResult?, Error?).self) { group in
                for (index, delivery) in session.deliveries.enumerated() {
                    guard delivery.status == .success, let clipURL = delivery.videoURL else { continue }
                    guard let target = challengeTargetBySequence[delivery.sequence] else { continue }

                    group.addTask { [analysisService] in
                        do {
                            let result = try await analysisService.evaluateChallenge(clipURL: clipURL, target: target)
                            return (index, target, result, nil)
                        } catch {
                            return (index, target, nil, error)
                        }
                    }
                }

                for await (index, target, result, error) in group {
                    if let result {
                        session.recordChallengeResult(hit: result.matchesTarget)
                        let challengeText = ChallengeEngine.formatResult(target: target, result: result)
                        if let existing = session.deliveries[index].report, !existing.isEmpty {
                            session.deliveries[index].report = "\(existing) • \(challengeText)"
                        } else {
                            session.deliveries[index].report = challengeText
                        }
                    } else {
                        log.error("D\(index + 1) challenge evaluation failed: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }

        // Phase 3: Extract BowlingDNA in parallel for each delivery with a clip
        await withTaskGroup(of: (Int, BowlingDNA?).self) { group in
            for (index, delivery) in session.deliveries.enumerated() {
                guard delivery.status == .success, let clipURL = delivery.videoURL else { continue }
                group.addTask { [analysisService] in
                    do {
                        let dna = try await analysisService.extractBowlingDNA(
                            clipURL: clipURL,
                            wristOmega: delivery.wristOmega,
                            releaseWristY: delivery.releaseWristY
                        )
                        return (index, dna)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            for await (index, dna) in group {
                if let dna {
                    session.deliveries[index].dna = dna
                    session.deliveries[index].dnaMatches = BowlingDNAMatcher.match(userDNA: dna, topN: 3)
                    log.debug("D\(index + 1) DNA extracted, top match: \(self.session.deliveries[index].dnaMatches?.first?.bowlerName ?? "none")")
                }
            }
        }

        // Phase 4: Generate session summary
        do {
            let summary = try await analysisService.generateSessionSummary(deliveries: session.deliveries)
            let challengeScore = session.mode == .challenge && session.challengeTotal > 0
                ? session.challengeScoreText
                : nil
            session.summary = SessionSummary(
                totalDeliveries: summary.totalDeliveries,
                durationMinutes: summary.durationMinutes,
                dominantPace: summary.dominantPace,
                paceDistribution: summary.paceDistribution,
                keyObservation: summary.keyObservation,
                challengeScore: challengeScore
            )
            log.info("Session summary generated")
        } catch {
            log.warning("Session summary generation failed: \(error.localizedDescription)")
        }

        isAnalyzing = false
        log.info("Post-session analysis complete")
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

        let prompt = Self.proactiveGreetingPrompt(
            mode: session.mode,
            challengeTarget: currentChallengeTarget
        )
        await liveService.sendContext(prompt)
        didSendProactiveGreeting = true
        flowPhase = .planning
        hasBowlerPlanResponse = false
        proactiveRepromptTask?.cancel()
        proactiveRepromptTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self?.sendPlanningRepromptIfNeeded()
        }
    }

    static func proactiveGreetingPrompt(mode: SessionMode, challengeTarget: String?) -> String {
        if mode == .challenge {
            let targetLine: String
            if let challengeTarget, !challengeTarget.isEmpty {
                targetLine = "Current target (if asked): \(challengeTarget)."
            } else {
                targetLine = "No target yet. Set first target only after pilot run."
            }
            return """
            Start now with a proactive greeting in one short sentence.
            Keep every response brief, natural, and non-robotic.
            Then do this exact sequence:
            1) Ask: "What's the plan for today?"
            2) Wait about 5 seconds for an answer. If no answer, ask once again naturally.
            3) Say this is challenge mode and ask if the bowler wants to stay in challenge or switch to free mode.
            4) If bowler asks to switch, call tool switch_session_mode with mode=free.
            5) Verify setup quickly (phone angle, full run-up/release visibility, lighting, distance).
            6) Ask for one pilot run to calibrate.
            7) After a good pilot run, explicitly say "Session started", then continue live feedback.
            \(targetLine)
            """
        }
        return """
        Start now with a proactive greeting in one short sentence.
        Keep every response brief, natural, and non-robotic.
        Then do this exact sequence:
        1) Ask: "What's the plan for today?"
        2) Wait about 5 seconds for an answer. If no answer, ask once again naturally.
        3) Ask if bowler wants free mode or challenge mode for this session.
        4) If bowler asks challenge, call tool switch_session_mode with mode=challenge.
        5) Verify setup quickly (phone angle, full run-up/release visibility, lighting, distance).
        6) Ask for one pilot run to calibrate.
        7) After a good pilot run, explicitly say "Session started", then continue live feedback.
        """
    }

    static func planningRepromptPrompt(mode: SessionMode) -> String {
        let modeLine = mode == .challenge ? "You are in challenge mode currently." : "You are in free mode currently."
        return """
        \(modeLine)
        No clear plan response yet. Ask again in one short natural sentence:
        "What's the plan for today?"
        """
    }

    static func setupVerificationPrompt(mode: SessionMode) -> String {
        let modeLine = mode == .challenge
        ? "Confirm this is challenge mode and remind they can switch to free mode anytime."
        : "Confirm this is free mode and remind they can switch to challenge mode anytime."
        return """
        Thanks for the plan. \(modeLine)
        Now verify setup quickly in one short line (angle, full run-up/release visibility, lighting, distance),
        then ask for one pilot run.
        """
    }

    static func postPilotPrompt(mode: SessionMode, target: String?) -> String {
        if mode == .challenge, let target, !target.isEmpty {
            return """
            Pilot run received. If setup is good, say "Session started" now.
            Then announce the challenge target briefly: \(target).
            """
        }
        return """
        Pilot run received. If setup is good, say "Session started" now
        and invite the next ball in one short line.
        """
    }

    private func sendPlanningRepromptIfNeeded() async {
        guard session.isActive else { return }
        guard liveService.isConnected else { return }
        guard flowPhase == .planning else { return }
        guard !hasBowlerPlanResponse else { return }
        await liveService.sendContext(Self.planningRepromptPrompt(mode: session.mode))
    }

    private func markPlanResponseAndContinueSetupIfNeeded() async {
        guard session.isActive else { return }
        guard liveService.isConnected else { return }
        guard !hasBowlerPlanResponse else { return }
        hasBowlerPlanResponse = true
        proactiveRepromptTask?.cancel()
        proactiveRepromptTask = nil
        flowPhase = .pilotRun
        await liveService.sendContext(Self.setupVerificationPrompt(mode: session.mode))
    }

    private func switchSessionMode(to mode: SessionMode) async -> Bool {
        guard session.isActive else { return false }
        guard session.mode != mode else { return true }

        session.mode = mode
        if mode == .freePlay {
            session.currentChallenge = nil
            currentChallengeTarget = nil
            await liveService.sendContext("Mode switched to free mode. Continue brief live feedback.")
            return true
        }

        challengeEngine.reset(shuffle: true)
        session.currentChallenge = nil
        currentChallengeTarget = nil
        challengeTargetBySequence = [:]

        if hasPilotRun {
            await issueNextChallengeTarget(isInitial: true)
            await liveService.sendContext("Mode switched to challenge mode. Challenge target is active.")
        } else {
            await liveService.sendContext("Mode switched to challenge mode. We will set challenge target after pilot run.")
        }
        return true
    }

    static func cameraSwitchContext(for position: AVCaptureDevice.Position) -> String {
        let label = position == .front ? "front" : "back"
        return "Camera switched to \(label) camera. Treat this active camera view as source of truth now and briefly acknowledge the switch."
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
        AudioSessionManager.shared.playPCMChunk(pcmData)
        Task { @MainActor in
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
            await markPlanResponseAndContinueSetupIfNeeded()
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
                errorMessage = "Disconnected: \(reason)"
                return
            }

            // Auto-reconnect while session is active (e.g. server goAway, iOS TCP abort)
            errorMessage = "Reconnecting..."
            debugLog += "Reconnecting...\n"

            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s backoff

            guard session.isActive else { return } // user may have ended session during backoff

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

    func voiceMate(didRequestModeSwitch mode: SessionMode) async -> Bool {
        await switchSessionMode(to: mode)
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
            let count = session.deliveryCount + 1
            let isPilotDelivery = !hasPilotRun
            var challengeTarget: String?
            if session.mode == .challenge {
                challengeTarget = session.currentChallenge
                if let target = challengeTarget {
                    challengeTargetBySequence[count] = target
                }
            }

            // Create delivery with MediaPipe-derived fields
            let delivery = Delivery(
                timestamp: timestamp,
                status: .clipping,
                sequence: count,
                wristOmega: wristOmega,
                releaseWristY: releaseWristY
            )
            session.addDelivery(delivery)

            log.info("Delivery #\(count) detected at \(timestamp)s (\(bowlingArm.rawValue) arm, \(paceBand.label))")

            // TTS: announce count only (pace is post-clip, per codex P1)
            tts.speak("\(count).")

            // Send context to Live API mate (enriches its understanding)
            if liveService.isConnected {
                var context = "Delivery \(count) just happened at \(String(format: "%.1f", timestamp)) seconds. " +
                "Bowling arm: \(bowlingArm.rawValue)."
                if let challengeTarget {
                    context += " Challenge target for this ball: \(challengeTarget)."
                }
                await liveService.sendContext(
                    context
                )
            }

            if isPilotDelivery {
                hasPilotRun = true
                flowPhase = .active

                if session.mode == .challenge {
                    await issueNextChallengeTarget(isInitial: true)
                    if liveService.isConnected {
                        await liveService.sendContext(
                            Self.postPilotPrompt(mode: .challenge, target: currentChallengeTarget)
                        )
                    }
                } else if liveService.isConnected {
                    await liveService.sendContext(
                        Self.postPilotPrompt(mode: .freePlay, target: nil)
                    )
                }
                return
            }

            if session.mode == .challenge {
                await issueNextChallengeTarget()
            }
        }
    }
}
