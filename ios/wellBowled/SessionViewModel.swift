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
    @Published var isPreparingClips: Bool = false
    @Published var clipPreparationProgress: Double = 0
    @Published private(set) var deepAnalysisStatusByDelivery: [UUID: DeliveryDeepAnalysisStatus] = [:]
    @Published private(set) var deepAnalysisArtifactsByDelivery: [UUID: DeliveryDeepAnalysisArtifacts] = [:]

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
    private var clipPreparationTask: Task<Void, Never>?
    private var deepAnalysisTasksByDelivery: [UUID: Task<Void, Never>] = [:]
    private var telemetryTasksByDelivery: [UUID: Task<Void, Never>] = [:]
    private var challengeEvaluatedDeliveries = Set<UUID>()

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
        clipPreparationTask?.cancel()
        clipPreparationTask = nil
        isPreparingClips = false
        clipPreparationProgress = 0
        isAnalyzing = false
        analysisProgress = 0
        cancelAllDeepAnalysisTasks(resetState: true)
        challengeEvaluatedDeliveries = []
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

        // Post-session: clip preparation only (deep analysis is on-demand per delivery).
        if let url = recordingURL, session.deliveryCount > 0 {
            startClipPreparation(recordingURL: url)
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

    // MARK: - Post-Session Preparation (Immediate)

    private func startClipPreparation(recordingURL: URL) {
        clipPreparationTask?.cancel()
        clipPreparationTask = Task { [weak self] in
            await self?.prepareDeliveryClips(recordingURL: recordingURL)
        }
    }

    private func prepareDeliveryClips(recordingURL: URL) async {
        guard !session.deliveries.isEmpty else { return }

        isPreparingClips = true
        clipPreparationProgress = 0
        let total = Double(max(session.deliveries.count, 1))
        let recordingOffset = CMTimeGetSeconds(recordingStartTime ?? .zero)
        let clipCounter = ActorCounter()

        await withTaskGroup(of: (Int, URL?, UIImage?, Error?).self) { group in
            for (index, delivery) in session.deliveries.enumerated() {
                group.addTask { [clipExtractor] in
                    let clipTimestamp = max(delivery.timestamp - recordingOffset, 0)
                    do {
                        let clipURL = try await clipExtractor.extractClip(from: recordingURL, at: clipTimestamp)
                        let thumbnail = ClipThumbnailGenerator.releaseThumbnail(from: clipURL)
                        return (index, clipURL, thumbnail, nil)
                    } catch {
                        return (index, nil, nil, error)
                    }
                }
            }

            for await (index, clipURL, thumbnail, error) in group {
                if let clipURL {
                    session.deliveries[index].videoURL = clipURL
                    session.deliveries[index].thumbnail = thumbnail
                    session.deliveries[index].status = .queued
                    deepAnalysisStatusByDelivery[session.deliveries[index].id] = DeliveryDeepAnalysisStatus(
                        stage: .idle,
                        elapsedSeconds: 0,
                        statusMessage: "",
                        failureMessage: nil
                    )
                } else {
                    session.deliveries[index].status = .failed
                    let message = error?.localizedDescription ?? "Clip preparation failed."
                    deepAnalysisStatusByDelivery[session.deliveries[index].id] = DeliveryDeepAnalysisStatus(
                        stage: .failed,
                        elapsedSeconds: 0,
                        statusMessage: "",
                        failureMessage: message
                    )
                    log.error("D\(index + 1) clip extraction failed: \(message)")
                }
                let completed = await clipCounter.increment()
                clipPreparationProgress = Double(completed) / total
            }
        }

        isPreparingClips = false
        refreshSessionSummary()
    }

    // MARK: - On-Demand Deep Analysis

    func deepAnalysisStatus(for deliveryID: UUID) -> DeliveryDeepAnalysisStatus {
        deepAnalysisStatusByDelivery[deliveryID] ?? DeliveryDeepAnalysisStatus()
    }

    func deepAnalysisArtifacts(for deliveryID: UUID) -> DeliveryDeepAnalysisArtifacts? {
        deepAnalysisArtifactsByDelivery[deliveryID]
    }

    func runDeepAnalysisIfNeeded(for deliveryID: UUID) async {
        if deepAnalysisTasksByDelivery[deliveryID] != nil { return }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runDeepAnalysis(for: deliveryID)
        }
        deepAnalysisTasksByDelivery[deliveryID] = task
        await task.value
    }

    func requestChipGuidance(for deliveryID: UUID, chip: String) async -> ChipGuidanceResponse {
        guard let delivery = session.deliveries.first(where: { $0.id == deliveryID }) else {
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
        do {
            let guidance = try await analysisService.generateChipGuidance(
                chip: chip,
                deliverySummary: summary,
                phases: phases
            )
            var artifacts = deepAnalysisArtifactsByDelivery[deliveryID] ?? DeliveryDeepAnalysisArtifacts()
            artifacts.chipReply = guidance.reply
            deepAnalysisArtifactsByDelivery[deliveryID] = artifacts
            return guidance
        } catch {
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

        var detailedResult: DeliveryDeepAnalysisResult?
        var dnaResult: BowlingDNA?
        var poseFrames: [FramePoseLandmarks] = []
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

            group.addTask { [analysisService, delivery = session.deliveries[index]] in
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
                    let frames = try await clipPoseExtractor.extractFrames(from: clipURL)
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
                case .detailed(.failure(let error)):
                    log.error("Deep analysis failed for D\(index + 1): \(error.localizedDescription)")
                case .dna(.success(let dna)):
                    dnaResult = dna
                case .dna(.failure(let error)):
                    log.warning("DNA extraction failed for D\(index + 1): \(error.localizedDescription)")
                case .pose(.success(let frames)):
                    poseFrames = frames
                case .pose(.failure(let error)):
                    log.warning("Pose extraction failed for D\(index + 1): \(error.localizedDescription)")
                case .challenge(.success(let result), let target):
                    session.recordChallengeResult(hit: result.matchesTarget)
                    challengeEvaluatedDeliveries.insert(deliveryID)
                    challengeText = ChallengeEngine.formatResult(target: target, result: result)
                case .challenge(.failure(let error), _):
                    log.warning("Challenge evaluation failed for D\(index + 1): \(error.localizedDescription)")
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
            session.deliveries[index].dnaMatches = BowlingDNAMatcher.match(userDNA: dna, topN: 3)
        }

        var artifacts = deepAnalysisArtifactsByDelivery[deliveryID] ?? DeliveryDeepAnalysisArtifacts()
        artifacts.poseFrames = poseFrames
        artifacts.expertAnalysis = detailedResult.expertAnalysis ?? ExpertAnalysisBuilder.build(from: detailedResult.phases)
        deepAnalysisArtifactsByDelivery[deliveryID] = artifacts

        deepAnalysisStatusByDelivery[deliveryID] = DeliveryDeepAnalysisStatus(
            stage: .ready,
            elapsedSeconds: 0,
            statusMessage: "Deep analysis ready",
            failureMessage: nil
        )

        deepAnalysisTasksByDelivery[deliveryID] = nil
        refreshSessionSummary()
    }

    private func startTelemetry(for deliveryID: UUID) {
        stopTelemetry(for: deliveryID)
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
    }

    private func cancelAllDeepAnalysisTasks(resetState: Bool) {
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

        let observation = analyzed.last?.report ?? "Tap Deep Analysis on a delivery to generate coaching insights."
        let challengeScore = session.mode == .challenge && session.challengeTotal > 0 ? session.challengeScoreText : nil
        session.summary = SessionSummary(
            totalDeliveries: session.deliveryCount,
            durationMinutes: max(session.duration / 60.0, 0),
            dominantPace: dominant,
            paceDistribution: paceDistribution,
            keyObservation: observation,
            challengeScore: challengeScore
        )
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

    static func shouldEndSession(from transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }
        let phrases = [
            "end session",
            "end the session",
            "stop session",
            "stop the session",
            "finish session",
            "finish the session",
            "wrap up session",
            "wrap up the session",
            "session over"
        ]

        return phrases.contains { normalized.contains($0) }
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
            if Self.shouldEndSession(from: text) {
                await endSession()
                return
            }
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
            deepAnalysisStatusByDelivery[delivery.id] = DeliveryDeepAnalysisStatus(
                stage: .idle,
                elapsedSeconds: 0,
                statusMessage: "",
                failureMessage: nil
            )

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
