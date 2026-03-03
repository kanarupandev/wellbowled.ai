import SwiftUI
import AVFoundation

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)

/// Full-screen camera with Live API voice session + delivery detection overlay.
struct LiveSessionView: View {
    @StateObject private var viewModel = SessionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showResults = false
    @State private var deliveryFlashCount: Int?
    @State private var didAttemptAutoStart = false
    @State private var isAutoStarting = false
    let initialMode: SessionMode

    init(initialMode: SessionMode = .freePlay) {
        self.initialMode = initialMode
    }

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            CameraPreviewLayer(previewLayer: viewModel.cameraService.previewLayer)
                .ignoresSafeArea()

            // Delivery flash overlay (large centered count that fades)
            if let count = deliveryFlashCount {
                Text("\(count)")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(peacockBlue)
                    .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
                    .transition(.scale.combined(with: .opacity))
            }

            // Overlay
            VStack(spacing: 0) {
                // Top bar: connection status + delivery count + timer
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.session.mode.finePrintLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(peacockBlue)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            Text(statusText)
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    // Delivery count badge
                    if viewModel.session.deliveryCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "cricket.ball")
                                .font(.caption)
                            Text("\(viewModel.session.deliveryCount)")
                                .font(.title3.bold().monospacedDigit())
                        }
                        .foregroundColor(peacockBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(peacockBlue.opacity(0.15)))
                    }

                    // Session countdown
                    if viewModel.session.isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption)
                            Text(viewModel.sessionRemainingText)
                                .font(.caption.bold().monospacedDigit())
                        }
                        .foregroundColor(timerColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial.opacity(0.7))

                if isChallengeSession {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.caption)
                        Text(challengeBannerText)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                    .foregroundColor(peacockBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.45))
                }

                Spacer()

                // Transcript overlay
                if !viewModel.lastTranscript.isEmpty {
                    Text(viewModel.lastTranscript)
                        .font(.callout)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Speaking indicator
                if viewModel.isMateSpeaking {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(peacockBlue)
                                .frame(width: 3, height: 10)
                                .animation(
                                    .easeInOut(duration: 0.4)
                                    .repeatForever()
                                    .delay(Double(i) * 0.15),
                                    value: viewModel.isMateSpeaking
                                )
                        }
                        Text("Mate is speaking")
                            .font(.caption2)
                            .foregroundColor(peacockBlue)
                    }
                    .padding(.top, 4)
                }

                // Error / reconnecting banner
                if let error = viewModel.errorMessage {
                    HStack(spacing: 6) {
                        if error.contains("Reconnecting") {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.yellow)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(error.contains("Reconnecting") ? .yellow : .red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }

                // Analysis progress
                if viewModel.isAnalyzing {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.analysisProgress)
                            .tint(peacockBlue)
                        Text("Analyzing deliveries...")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                }

                // Bottom controls
                HStack(spacing: 20) {
                    // Close
                    Button {
                        Task {
                            await viewModel.endSession()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }

                    // Main action button
                    Button {
                        Task {
                            if isSessionActive {
                                await viewModel.endSession()
                                if viewModel.session.deliveryCount > 0 {
                                    showResults = true
                                }
                            } else if !isAutoStarting {
                                await viewModel.startSession(mode: initialMode)
                            }
                        }
                    } label: {
                        Text(mainActionTitle)
                            .font(.headline)
                            .foregroundColor(mainActionTextColor)
                            .frame(width: 100, height: 50)
                            .background(
                                Capsule().fill(mainActionColor)
                            )
                    }
                    .disabled(isAutoStarting)

                    // Camera flip button
                    Button {
                        viewModel.toggleCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                }
                .padding(.bottom, 30)
                .padding(.top, 12)

                // Results button (floats above controls when available)
                if viewModel.session.deliveryCount > 0 && !viewModel.session.isActive && !viewModel.isAnalyzing {
                    Button {
                        showResults = true
                    } label: {
                        Label("View Results", systemImage: "list.bullet")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(peacockBlue))
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .statusBarHidden(true)
        .sheet(isPresented: $showResults) {
            SessionResultsView(viewModel: viewModel)
        }
        .onChange(of: viewModel.session.isActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            if viewModel.session.deliveryCount > 0 && !viewModel.isAnalyzing {
                showResults = true
            }
        }
        .onChange(of: viewModel.isAnalyzing) { wasAnalyzing, isAnalyzing in
            guard wasAnalyzing, !isAnalyzing else { return }
            if viewModel.session.deliveryCount > 0 && !viewModel.session.isActive {
                showResults = true
            }
        }
        .onChange(of: viewModel.session.deliveryCount) { _, newCount in
            guard newCount > 0 else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                deliveryFlashCount = newCount
            }
            // Auto-dismiss flash after 1.2s
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeOut(duration: 0.4)) {
                    deliveryFlashCount = nil
                }
            }
        }
        .onAppear {
            guard !didAttemptAutoStart else { return }
            didAttemptAutoStart = true
            isAutoStarting = true
            Task {
                await viewModel.startSession(mode: initialMode)
                isAutoStarting = false
            }
        }
        .onDisappear {
            Task { await viewModel.endSession() }
        }
    }

    // MARK: - Computed

    private var isSessionActive: Bool {
        viewModel.session.isActive
    }

    private var isChallengeSession: Bool {
        viewModel.session.mode == .challenge || (!viewModel.session.isActive && initialMode == .challenge)
    }

    private var challengeBannerText: String {
        if let target = viewModel.currentChallengeTarget, !target.isEmpty {
            return "Target: \(target)"
        }
        return viewModel.session.isActive ? "Waiting for first target..." : "Challenge mode"
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected: return peacockBlue
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch viewModel.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error(let msg): return msg
        }
    }

    private var timerColor: Color {
        if viewModel.sessionRemainingSeconds <= 15 { return .red }
        if viewModel.sessionRemainingSeconds <= 45 { return .yellow }
        return .white
    }

    private var mainActionTitle: String {
        if isSessionActive { return "End" }
        if isAutoStarting { return "Starting..." }
        return "Restart"
    }

    private var mainActionColor: Color {
        if isSessionActive { return .red }
        if isAutoStarting { return Color.gray.opacity(0.55) }
        return peacockBlue
    }

    private var mainActionTextColor: Color {
        isSessionActive ? .white : .black
    }
}

// MARK: - Session Results

struct SessionResultsView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDeliveryIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SessionResultsHeaderCard(session: viewModel.session)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if let topMatch = viewModel.session.deliveries
                    .compactMap(\.dnaMatches)
                    .first?
                    .first {
                    SessionDNASummaryCard(match: topMatch)
                        .padding(.horizontal, 12)
                }

                if viewModel.isPreparingClips {
                    HStack(spacing: 8) {
                        ProgressView(value: viewModel.clipPreparationProgress)
                            .tint(peacockBlue)
                        Text("Preparing delivery clips...")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 12)
                }

                if viewModel.session.deliveries.isEmpty {
                    ContentUnavailableView(
                        "No Deliveries",
                        systemImage: "figure.cricket",
                        description: Text("Run a short session to generate delivery clips.")
                    )
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $selectedDeliveryIndex) {
                        ForEach(Array(viewModel.session.deliveries.enumerated()), id: \.element.id) { index, delivery in
                            SessionDeliveryResultPage(viewModel: viewModel, deliveryID: delivery.id)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 20)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Session Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SessionResultsHeaderCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(session.deliveryCount) deliveries", systemImage: "cricket.ball")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()

                if session.duration > 0 {
                    Text(formatDuration(session.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            if let summary = session.summary {
                HStack {
                    Text(summary.dominantPace.label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(peacockBlue)
                    Spacer()
                    if let challengeScore = summary.challengeScore {
                        Text(challengeScore)
                            .font(.caption.weight(.bold))
                            .foregroundColor(peacockBlue)
                    }
                }

                if !summary.keyObservation.isEmpty {
                    Text(summary.keyObservation)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

private struct SessionDNASummaryCard: View {
    let match: BowlingDNAMatch

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.cricket")
                .foregroundColor(peacockBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Action signature: \(Int(match.similarityPercent))% \(match.bowlerName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Closest phase: \(match.closestPhase)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SessionDeliveryResultPage: View {
    @ObservedObject var viewModel: SessionViewModel
    let deliveryID: UUID

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var syncController: SkeletonSyncController?
    @State private var poseFrames: [FramePoseLandmarks] = []
    @State private var expertAnalysis: ExpertAnalysis?
    @State private var poseNote = "Run Deep Analysis to generate pose annotation."
    @State private var focusLoopTask: Task<Void, Never>?
    @State private var selectedFocusChipID: String?
    @State private var focusWindow: ClosedRange<Double>?
    @State private var isPlaybackPaused = false
    @State private var isSlowMotion = false
    @State private var showCoachChips = false
    @State private var chipReply = ""

    private var delivery: Delivery? {
        viewModel.session.deliveries.first(where: { $0.id == deliveryID })
    }

    private var phases: [AnalysisPhase] {
        ((delivery?.phases) ?? [])
            .sorted { ($0.clipTimestamp ?? .greatestFiniteMagnitude) < ($1.clipTimestamp ?? .greatestFiniteMagnitude) }
    }

    private var deepStatus: DeliveryDeepAnalysisStatus {
        viewModel.deepAnalysisStatus(for: deliveryID)
    }

    private var focusSuggestions: [SessionPhaseSuggestion] {
        SessionResultsPlanner.topPhaseSuggestions(phases: phases, expertAnalysis: expertAnalysis)
    }

    private var deepAnalysisReady: Bool {
        deepStatus.stage == .ready && !phases.isEmpty
    }

    private var chatChips: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in focusSuggestions.map(\.phaseName) + ["Pause", "Slow-mo"] {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    var body: some View {
        Group {
            if let delivery {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        SessionDeliveryClipCard(
                            delivery: delivery,
                            player: player,
                            syncController: syncController,
                            isPoseLoading: deepStatus.stage == .running
                        )

                        deepAnalysisStatusSection(for: delivery)

                        if deepAnalysisReady {
                            swipeHint
                        }

                        phaseAnalysisSection
                        dnaSection(for: delivery)
                        poseAndControlSection
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .onAppear {
                    setupPlayerIfNeeded()
                    refreshArtifactsFromViewModel()
                }
                .onReceive(viewModel.$deepAnalysisArtifactsByDelivery) { _ in
                    refreshArtifactsFromViewModel()
                }
                .onChange(of: delivery.videoURL) { _, _ in
                    setupPlayerIfNeeded()
                }
                .onDisappear {
                    teardownPlayback()
                }
            } else {
                ContentUnavailableView(
                    "Delivery Unavailable",
                    systemImage: "exclamationmark.circle",
                    description: Text("This delivery is no longer available.")
                )
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func deepAnalysisStatusSection(for delivery: Delivery) -> some View {
        switch deepStatus.stage {
        case .idle:
            if delivery.videoURL != nil {
                Button {
                    Task {
                        await viewModel.runDeepAnalysisIfNeeded(for: deliveryID)
                    }
                } label: {
                    Label("Run Deep Analysis", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(peacockBlue))
                }
            } else {
                SessionDeepAnalysisPendingCard(
                    message: viewModel.isPreparingClips ? "Preparing 5-second clip and release thumbnail..." : "Waiting for clip preparation.",
                    elapsedSeconds: 0
                )
            }
        case .running:
            SessionDeepAnalysisPendingCard(
                message: deepStatus.statusMessage.isEmpty ? "Analyzing..." : deepStatus.statusMessage,
                elapsedSeconds: deepStatus.elapsedSeconds
            )
        case .ready:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text(deepStatus.failureMessage ?? "Deep analysis failed.")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.9))
                Button {
                    Task {
                        await viewModel.runDeepAnalysisIfNeeded(for: deliveryID)
                    }
                } label: {
                    Label("Retry Deep Analysis", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(peacockBlue))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private var swipeHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.compact.down")
                .font(.body.weight(.semibold))
                .foregroundColor(peacockBlue)
            Text("Swipe down for phase insights")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.86))
        }
    }

    private var phaseAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phase analysis")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            if phases.isEmpty {
                Text("Run Deep Analysis to view phase-wise good, bad, and injury-risk insights.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            } else {
                ForEach(phases) { phase in
                    SessionPhaseFeedbackCard(
                        phase: phase,
                        phaseFeedback: feedbackForPhase(phase)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func dnaSection(for delivery: Delivery) -> some View {
        if let matches = delivery.dnaMatches, !matches.isEmpty {
            SessionDNAMatchCarousel(matches: matches)
        } else if deepStatus.stage == .running {
            Text("Compiling action signature vector and matching bowler profiles...")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.68))
        } else if deepAnalysisReady {
            Text("No DNA match available for this delivery yet.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.68))
        }
    }

    private var poseAndControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pose annotated playback")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.92))

            FinePrintOverlayLegend()

            if !focusSuggestions.isEmpty {
                SessionVideoControlChips(
                    suggestions: focusSuggestions,
                    selectedFocusChipID: selectedFocusChipID,
                    isPaused: isPlaybackPaused,
                    isSlowMotion: isSlowMotion,
                    onFocusTap: { suggestion in
                        toggleFocusSuggestion(suggestion)
                    },
                    onPauseTap: {
                        togglePause()
                    },
                    onSlowMoTap: {
                        toggleSlowMotion()
                    }
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCoachChips.toggle()
                }
            } label: {
                Label(showCoachChips ? "Hide Chat Controls" : "Show Chat Controls", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(peacockBlue))
            }

            if showCoachChips {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.cursor")
                            .foregroundColor(.white.opacity(0.7))
                        Text("Chat input is chip-only in this version.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.74))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chatChips, id: \.self) { chip in
                                Button {
                                    Task {
                                        let guidance = await viewModel.requestChipGuidance(for: deliveryID, chip: chip)
                                        await apply(guidance: guidance)
                                    }
                                } label: {
                                    Text(chip)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(Color.white))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !chipReply.isEmpty {
                        Text(chipReply)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.86))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    }
                }
            }

            Text(poseNote)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 18)
        }
    }

    private func setupPlayerIfNeeded() {
        guard player == nil, let url = delivery?.videoURL else { return }

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true
        player = queuePlayer
        applyPlaybackMode()
        rebuildSyncControllerIfPossible()
    }

    private func refreshArtifactsFromViewModel() {
        guard let artifacts = viewModel.deepAnalysisArtifacts(for: deliveryID) else {
            if phases.isEmpty {
                poseNote = "Run Deep Analysis to generate pose annotation."
            } else {
                expertAnalysis = ExpertAnalysisBuilder.build(from: phases)
            }
            rebuildSyncControllerIfPossible()
            return
        }

        if !artifacts.poseFrames.isEmpty {
            poseFrames = artifacts.poseFrames
            poseNote = "Pose overlay generated from local MediaPipe extraction."
        } else if deepStatus.stage == .ready {
            poseNote = "Pose overlay unavailable for this delivery."
        }

        if let analysis = artifacts.expertAnalysis {
            expertAnalysis = analysis
        } else {
            expertAnalysis = ExpertAnalysisBuilder.build(from: phases)
        }

        if let reply = artifacts.chipReply {
            chipReply = reply
        }
        rebuildSyncControllerIfPossible()
    }

    private func teardownPlayback() {
        focusLoopTask?.cancel()
        focusLoopTask = nil
        syncController?.cleanup()
        syncController = nil
        player?.pause()
        player = nil
        looper = nil
    }

    private func toggleFocusSuggestion(_ suggestion: SessionPhaseSuggestion) {
        if selectedFocusChipID == suggestion.id {
            clearFocusLoop()
            return
        }

        selectedFocusChipID = suggestion.id
        isPlaybackPaused = false
        let window = SessionResultsPlanner.focusWindow(
            for: suggestion.timestamp,
            clipDuration: clipDurationSeconds
        )
        focusWindow = window
        seek(to: window.lowerBound)
        applyPlaybackMode()
        startFocusLoop()
    }

    private func clearFocusLoop() {
        selectedFocusChipID = nil
        focusWindow = nil
        focusLoopTask?.cancel()
        focusLoopTask = nil
        applyPlaybackMode()
    }

    private func startFocusLoop() {
        focusLoopTask?.cancel()
        guard focusWindow != nil else { return }
        focusLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let player, let window = focusWindow else { continue }
                let current = player.currentTime().seconds
                if current.isFinite, current >= window.upperBound {
                    player.seek(
                        to: CMTime(seconds: window.lowerBound, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    ) { _ in
                    }
                }
            }
        }
    }

    private func togglePause() {
        isPlaybackPaused.toggle()
        if isPlaybackPaused {
            focusLoopTask?.cancel()
        } else if focusWindow != nil {
            startFocusLoop()
        }
        applyPlaybackMode()
    }

    private func toggleSlowMotion() {
        isSlowMotion.toggle()
        applyPlaybackMode()
    }

    private func applyPlaybackMode() {
        guard let player else { return }
        if isPlaybackPaused {
            player.pause()
            return
        }

        let rate: Float = isSlowMotion ? 0.45 : 1.0
        player.playImmediately(atRate: rate)
    }

    private var clipDurationSeconds: Double {
        guard let player else { return 5.0 }
        let duration = player.currentItem?.asset.duration.seconds ?? 5.0
        if duration.isFinite, duration > 0 {
            return duration
        }
        return 5.0
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in
        }
    }

    private func rebuildSyncControllerIfPossible() {
        guard let player, !poseFrames.isEmpty else { return }
        syncController?.cleanup()
        syncController = SkeletonSyncController(
            player: player,
            frames: poseFrames,
            expertAnalysis: expertAnalysis
        )
    }

    private func feedbackForPhase(_ phase: AnalysisPhase) -> ExpertAnalysis.Phase.Feedback? {
        guard let expert = matchingExpertPhase(for: phase) else { return nil }
        return expert.feedback
    }

    private func matchingExpertPhase(for phase: AnalysisPhase) -> ExpertAnalysis.Phase? {
        guard let expertAnalysis else { return nil }
        let normalizedPhaseName = normalized(phase.name)
        if let exact = expertAnalysis.phases.first(where: { normalized($0.phaseName) == normalizedPhaseName }) {
            return exact
        }
        return expertAnalysis.phases.first {
            normalized($0.phaseName).contains(normalizedPhaseName) ||
            normalizedPhaseName.contains(normalized($0.phaseName))
        }
    }

    private func normalized(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    @MainActor
    private func apply(guidance: ChipGuidanceResponse) {
        chipReply = guidance.reply
        let action = guidance.action.lowercased()

        switch action {
        case "pause":
            isPlaybackPaused = true
            applyPlaybackMode()
        case "slow_mo":
            isPlaybackPaused = false
            isSlowMotion = true
            applyPlaybackMode()
        case "focus":
            isPlaybackPaused = false
            let start = max(guidance.focusStart ?? 2.0, 0)
            let end = min(guidance.focusEnd ?? (start + 0.8), clipDurationSeconds)
            focusWindow = start...max(end, start + 0.2)
            selectedFocusChipID = guidance.phaseName?.lowercased()
            seek(to: focusWindow?.lowerBound ?? start)
            applyPlaybackMode()
            startFocusLoop()
        default:
            break
        }
    }
}

private struct SessionDeliveryClipCard: View {
    let delivery: Delivery
    let player: AVQueuePlayer?
    let syncController: SkeletonSyncController?
    let isPoseLoading: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let player {
                    CustomVideoPlayer(player: player)
                } else if delivery.videoURL != nil {
                    Color.black
                        .overlay {
                            ProgressView().tint(.white)
                        }
                } else {
                    Color.black
                        .overlay {
                            if delivery.status == .clipping || delivery.status == .queued {
                                VStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Preparing clip")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.78))
                                }
                            } else {
                                Text("Clip unavailable")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let syncController {
                SyncedSkeletonOverlayView(syncController: syncController)
            }

            VStack {
                HStack {
                    Spacer()
                    if let thumbnail = delivery.thumbnail {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Release")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white.opacity(0.88))
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 84, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .padding(10)
                    }
                }
                Spacer()
            }

            if isPoseLoading {
                VStack {
                    HStack {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Loading pose overlay")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(10)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Text("Delivery #\(delivery.sequence)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.55)))

                if let speed = delivery.speed {
                    Text(speed)
                        .font(.caption2.bold())
                        .foregroundColor(peacockBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                }

                Text("5s (3s run-up + 2s follow-through)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.88))
            }
            .padding(10)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct FinePrintOverlayLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            legendItem(text: "Red injury risk", color: .red)
            legendItem(text: "Green good", color: .green)
            legendItem(text: "Yellow attention", color: .yellow)
        }
        .font(.caption2)
        .foregroundColor(.white.opacity(0.82))
    }

    private func legendItem(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct SessionDeepAnalysisPendingCard: View {
    let message: String
    let elapsedSeconds: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(peacockBlue)
                .scaleEffect(0.9)

            VStack(alignment: .leading, spacing: 2) {
                Text("Deep expert analysis in progress")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer()

            Text("\(elapsedSeconds)s")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct SessionVideoControlChips: View {
    let suggestions: [SessionPhaseSuggestion]
    let selectedFocusChipID: String?
    let isPaused: Bool
    let isSlowMotion: Bool
    let onFocusTap: (SessionPhaseSuggestion) -> Void
    let onPauseTap: () -> Void
    let onSlowMoTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus suggestions")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.86))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        SessionControlChip(
                            title: suggestion.phaseName,
                            subtitle: "Focus",
                            isSelected: selectedFocusChipID == suggestion.id,
                            color: peacockBlue
                        ) {
                            onFocusTap(suggestion)
                        }
                    }

                    SessionControlChip(
                        title: "Pause",
                        subtitle: "Playback",
                        isSelected: isPaused,
                        color: .orange
                    ) {
                        onPauseTap()
                    }

                    SessionControlChip(
                        title: "Slow-mo",
                        subtitle: "Phase",
                        isSelected: isSlowMotion,
                        color: .yellow
                    ) {
                        onSlowMoTap()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct SessionControlChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .black : .white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .black.opacity(0.75) : .white.opacity(0.72))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? color : Color.white.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SessionDNAMatchCarousel: View {
    let matches: [BowlingDNAMatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action signature match")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            ForEach(matches.prefix(3)) { match in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 4)
                                .frame(width: 44, height: 44)
                            Circle()
                                .trim(from: 0, to: CGFloat(match.similarityPercent / 100.0))
                                .stroke(peacockBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 44, height: 44)
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(match.similarityPercent))%")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(match.bowlerName)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                            Text("\(match.country) • \(match.style)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                            Text("Closest phase: \(match.closestPhase)")
                                .font(.caption2)
                                .foregroundColor(peacockBlue)
                        }
                        Spacer()
                    }

                    if !match.signatureTraits.isEmpty {
                        Text(match.signatureTraits.prefix(2).joined(separator: " • "))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.78))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
        }
    }
}

private struct SessionPhaseFeedbackCard: View {
    let phase: AnalysisPhase
    let phaseFeedback: ExpertAnalysis.Phase.Feedback?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(phase.status)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(phase.isGood ? .green : .yellow)
            }

            SessionFeedbackLine(
                title: "Pro",
                text: proComment,
                color: .green
            )
            SessionFeedbackLine(
                title: "Con",
                text: conComment,
                color: .yellow
            )
            SessionFeedbackLine(
                title: "Injury risk",
                text: injuryRiskComment,
                color: .red
            )
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var proComment: String {
        if phase.isGood {
            return firstNonEmpty([
                phase.observation,
                phase.tip,
                "Gemini marked this phase as technically stable."
            ])
        }
        if let joints = phaseFeedback?.good, !joints.isEmpty {
            return "Stable joints: \(formattedJoints(joints))."
        }
        return "Phase captured clearly for focused correction."
    }

    private var conComment: String {
        if !phase.isGood {
            return firstNonEmpty([
                phase.observation,
                phase.tip,
                "Gemini marked this phase for attention."
            ])
        }
        if let joints = phaseFeedback?.slow, !joints.isEmpty {
            return "Attention joints: \(formattedJoints(joints))."
        }
        return "No major downside flagged in this phase."
    }

    private var injuryRiskComment: String {
        if let joints = phaseFeedback?.injuryRisk, !joints.isEmpty {
            return "Gemini risk flags: \(formattedJoints(joints))."
        }
        if !phase.isGood {
            return "No explicit injury-risk joints flagged yet; monitor this phase under load."
        }
        return "No injury-risk joints flagged by Gemini."
    }

    private func firstNonEmpty(_ candidates: [String]) -> String {
        candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }

    private func formattedJoints(_ joints: [String]) -> String {
        joints
            .prefix(3)
            .map { $0.replacingOccurrences(of: "_", with: " ").lowercased() }
            .joined(separator: ", ")
    }
}

private struct SessionFeedbackLine: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(text)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewLayer: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}
