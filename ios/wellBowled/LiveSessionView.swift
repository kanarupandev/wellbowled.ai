import SwiftUI
import AVFoundation
import os

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)
private let liveViewLog = Logger(subsystem: "com.wellbowled", category: "LiveSessionView")

/// Full-screen camera with Live API voice session + delivery detection overlay.
struct LiveSessionView: View {
    @StateObject private var viewModel = SessionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showResults = false
    @State private var deliveryFlashCount: Int?
    @State private var didAttemptAutoStart = false
    @State private var isAutoStarting = false
    @State private var isExitingToHome = false

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            GeometryReader { proxy in
                CameraPreview(previewLayer: viewModel.cameraService.previewLayer)
                    .frame(
                        width: max(proxy.size.width, 1),
                        height: max(proxy.size.height, 1)
                    )
            }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Calibration corridor overlay (TV broadcast style)
            if isSessionActive, WBConfig.enableSpeedCalibration {
                let overlayMode: CalibrationOverlayView.OverlayMode = {
                    switch viewModel.calibrationState {
                    case .locked: return .active
                    case .detecting: return .calibrating
                    case .idle, .failed: return viewModel.session.calibration != nil ? .active : .calibrating
                    }
                }()
                CalibrationOverlayView(
                    mode: overlayMode,
                    calibrationState: viewModel.calibrationState,
                    bowlerGuideRect: StumpDetectionService.defaultBowlerGuideRect(),
                    strikerGuideRect: StumpDetectionService.defaultStrikerGuideRect(),
                    onManualTap: nil
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.5), value: viewModel.calibrationState)
            }

            // Delivery flash overlay (large centered count that fades)
            if let count = deliveryFlashCount {
                Text("\(count)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [peacockBlue, .cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: peacockBlue.opacity(0.6), radius: 20, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }

            // Overlay
            VStack(spacing: 0) {
                // Top bar: connection status + delivery count + timer
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Session")
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
                            .symbolEffect(.pulse, isActive: viewModel.currentChallengeTarget != nil)
                        Text(challengeBannerText)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer()
                        if !viewModel.session.challengeScoreText.isEmpty {
                            Text(viewModel.session.challengeScoreText)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.green)
                        }
                    }
                    .foregroundColor(peacockBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.45))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: viewModel.currentChallengeTarget)
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

                // Speaking indicator — waveform style
                if viewModel.isMateSpeaking {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [peacockBlue, .cyan],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: 3, height: speakingBarHeight(for: i))
                                .animation(
                                    .easeInOut(duration: [0.35, 0.45, 0.3, 0.5, 0.4][i])
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.1),
                                    value: viewModel.isMateSpeaking
                                )
                        }
                        Text("Mate")
                            .font(.caption2.bold())
                            .foregroundColor(peacockBlue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
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
                            await viewModel.disconnectMate()
                            liveViewLog.debug("Close button tapped: ending session and dismissing live view")
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }

                    // Main action button
                    Button {
                        Task {
                            if isSessionActive {
                                liveViewLog.debug("Main action tapped in active session: ending session")
                                await viewModel.endSession()
                                showResults = true
                                liveViewLog.debug("Opening results sheet after manual end")
                            } else if !isAutoStarting {
                                liveViewLog.debug("Main action tapped in inactive session: restarting session")
                                await viewModel.startSession()
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

                    // Camera flip button (one flip per session)
                    Button {
                        liveViewLog.debug("Camera flip button tapped")
                        viewModel.toggleCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3)
                            .foregroundColor(viewModel.cameraFlipDisabled ? .gray : .white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .disabled(viewModel.cameraFlipDisabled)
                }
                .padding(.bottom, 30)
                .padding(.top, 12)

                // Results button (floats above controls when available)
                if viewModel.session.deliveryCount > 0 && !viewModel.session.isActive && !viewModel.isAnalyzing {
                    Button {
                        liveViewLog.debug("View Results button tapped")
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
            SessionResultsView(
                viewModel: viewModel,
                onExitToHome: {
                    Task { await exitToHome() }
                }
            )
            .interactiveDismissDisabled(true)
        }
        .onChange(of: showResults) { _, isPresented in
            liveViewLog.debug("Results sheet visibility changed: isPresented=\(isPresented)")
        }
        .onChange(of: viewModel.session.isActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            liveViewLog.debug("Auto-opening results on session transition to inactive")
            showResults = true
        }
        .onChange(of: viewModel.isAnalyzing) { wasAnalyzing, isAnalyzing in
            guard wasAnalyzing, !isAnalyzing else { return }
            if viewModel.session.deliveryCount > 0 && !viewModel.session.isActive {
                liveViewLog.debug("Auto-opening results after analysis completion")
                showResults = true
            }
        }
        .onChange(of: viewModel.session.deliveryCount) { _, newCount in
            guard newCount > 0 else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5, blendDuration: 0.1)) {
                deliveryFlashCount = newCount
            }
            // Auto-dismiss flash after 1.5s
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeOut(duration: 0.5)) {
                    deliveryFlashCount = nil
                }
            }
        }
        .onAppear {
            guard !didAttemptAutoStart else { return }
            didAttemptAutoStart = true
            isAutoStarting = true
            liveViewLog.debug("LiveSessionView appeared: auto-starting session")
            Task {
                await viewModel.startSession()
                isAutoStarting = false
            }
        }
        .onDisappear {
            liveViewLog.debug("LiveSessionView disappeared: ensuring session and mate are ended")
            Task {
                await viewModel.endSession()
                await viewModel.disconnectMate()
            }
        }
    }

    // MARK: - Helpers

    private func speakingBarHeight(for index: Int) -> CGFloat {
        [8, 14, 18, 12, 10][index]
    }

    // MARK: - Computed

    private var isSessionActive: Bool {
        viewModel.session.isActive
    }

    private var isChallengeSession: Bool {
        viewModel.session.mode == .challenge
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

    private func exitToHome() async {
        guard !isExitingToHome else { return }
        isExitingToHome = true
        defer { isExitingToHome = false }

        showResults = false
        await viewModel.endSession()
        await viewModel.disconnectMate()
        liveViewLog.debug("Exiting to Home from LiveSessionView")
        dismiss()
    }
}

// MARK: - Session Results

struct SessionResultsView: View {
    @ObservedObject var viewModel: SessionViewModel
    let onExitToHome: () -> Void
    @State private var selectedDeliveryIndex = 0

    private var deliveries: [Delivery] { viewModel.session.deliveries }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Mate transcript overlay (persistent voice in review mode)
            if viewModel.matePhase == .postSessionReview && !viewModel.lastTranscript.isEmpty {
                VStack {
                    Spacer()
                    Text(viewModel.lastTranscript)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.75))
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.lastTranscript)
                .zIndex(100)
            }

            if deliveries.isEmpty {
                // Clip preparation state
                VStack(spacing: 14) {
                    if viewModel.isPreparingClips {
                        ProgressView().tint(peacockBlue)
                        Text(viewModel.clipPreparationStatusMessage.isEmpty
                             ? "Detecting and clipping deliveries..."
                             : viewModel.clipPreparationStatusMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    } else {
                        Image(systemName: "figure.cricket")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.5))
                        Text("No deliveries found")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Button { onExitToHome() } label: {
                        Label("Home", systemImage: "house.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(peacockBlue))
                    }
                    .padding(.top, 8)
                }
            } else {
                // Horizontal delivery carousel (full screen)
                TabView(selection: $selectedDeliveryIndex) {
                    ForEach(Array(deliveries.enumerated()), id: \.element.id) { index, delivery in
                        SessionDeliveryResultPage(
                            viewModel: viewModel,
                            deliveryID: delivery.id,
                            onExitToHome: onExitToHome
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // Pagination dots — bottom center, overlayed
                if deliveries.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(deliveries.indices, id: \.self) { i in
                                Capsule()
                                    .fill(i == selectedDeliveryIndex ? peacockBlue : .white.opacity(0.28))
                                    .frame(width: i == selectedDeliveryIndex ? 20 : 7, height: 7)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: selectedDeliveryIndex)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .onChange(of: selectedDeliveryIndex) { _, newIndex in
            Task { await viewModel.reviewDelivery(at: newIndex) }
        }
        .onChange(of: viewModel.reviewDeliveryIndex) { _, newIndex in
            // Mate navigated via voice — sync the carousel
            if newIndex != selectedDeliveryIndex && newIndex < deliveries.count {
                withAnimation { selectedDeliveryIndex = newIndex }
            }
        }
    }
}

private struct SessionDeliveryResultPage: View {
    @ObservedObject var viewModel: SessionViewModel
    let deliveryID: UUID
    let onExitToHome: () -> Void

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
    @State private var playbackRate: Float = 1.0

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

    var body: some View {
        Group {
            if let delivery {
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // PAGE 1: Full-screen video with overlays
                            ZStack(alignment: .top) {
                                // Video layer (fills entire page)
                                SessionDeliveryClipCard(
                                    delivery: delivery,
                                    player: player,
                                    syncController: syncController,
                                    isPoseLoading: deepStatus.stage == .running
                                )

                                // Top bar: Home (left) + Save (right)
                                HStack {
                                    Button { onExitToHome() } label: {
                                        Image(systemName: "house.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(10)
                                            .background(Circle().fill(Color.black.opacity(0.45)))
                                    }
                                    Spacer()
                                    saveButton
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, geo.safeAreaInsets.top + 8)

                                // Speed badge (top-left, below home button)
                                if let speedKph = delivery.speedKph {
                                    VStack {
                                        HStack {
                                            SessionSpeedBadge(kph: speedKph, errorMarginKph: delivery.speedErrorMarginKph)
                                            Spacer()
                                        }
                                        .padding(.leading, 16)
                                        .padding(.top, geo.safeAreaInsets.top + 52)
                                        Spacer()
                                    }
                                }

                                // Right side: Deep Analysis button (vertically centered)
                                HStack {
                                    Spacer()
                                    deepAnalysisOverlayButton
                                }
                                .frame(maxHeight: .infinity)
                                .padding(.trailing, 12)

                                // Bottom 15% overlay area
                                VStack {
                                    Spacer()
                                    VStack(spacing: 6) {
                                        // Telemetry overlay (when running)
                                        if deepStatus.stage == .running {
                                            HStack(spacing: 6) {
                                                ProgressView().tint(.white).scaleEffect(0.6)
                                                Text("\(deepStatus.elapsedSeconds)s")
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundColor(.white.opacity(0.8))
                                                if !deepStatus.statusMessage.isEmpty {
                                                    Text(deepStatus.statusMessage)
                                                        .font(.caption2)
                                                        .foregroundColor(.white.opacity(0.65))
                                                        .lineLimit(1)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(Color.black.opacity(0.55)))
                                        }

                                        // Suggestion chips — only after analysis complete
                                        if deepAnalysisReady {
                                            videoOverlayChips
                                        }

                                        // Color legend — only after skeleton overlay
                                        if syncController != nil {
                                            FinePrintOverlayLegend()
                                        }

                                        // Swipe hint chevron
                                        Image(systemName: "chevron.compact.down")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    .padding(.bottom, 6)
                                }
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .padding(.bottom, geo.size.height * 0.01)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)

                            // PAGE 2: Detail content (swipe down)
                            detailPage
                                .frame(minHeight: geo.size.height)
                                .padding(.horizontal, 12)
                                .padding(.top, 20)
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .ignoresSafeArea()
                }
                .onAppear {
                    liveViewLog.info("SessionDeliveryResultPage appeared: deliveryID=\(deliveryID.uuidString.prefix(8), privacy: .public), hasVideo=\(delivery.videoURL != nil)")
                    setupPlayerIfNeeded()
                    refreshArtifactsFromViewModel()
                }
                .onReceive(viewModel.$deepAnalysisArtifactsByDelivery) { _ in
                    DispatchQueue.main.async { refreshArtifactsFromViewModel() }
                }
                .onReceive(viewModel.$session) { _ in
                    DispatchQueue.main.async { refreshArtifactsFromViewModel() }
                }
                .onChange(of: delivery.videoURL) { _, _ in
                    setupPlayerIfNeeded()
                }
                .onChange(of: viewModel.playbackCommand) { _, cmd in
                    guard let cmd else { return }
                    // Only respond if this delivery is currently being reviewed
                    guard viewModel.reviewDeliveryIndex < viewModel.session.deliveries.count,
                          viewModel.session.deliveries[viewModel.reviewDeliveryIndex].id == deliveryID else { return }
                    executePlaybackCommand(cmd)
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

    // MARK: - Overlay Buttons

    @ViewBuilder
    private var saveButton: some View {
        let status = viewModel.sessionVideoSaveStatus
        Button {
            liveViewLog.debug("Save button tapped: deliveryID=\(deliveryID.uuidString.prefix(8), privacy: .public), status=\(String(describing: status), privacy: .public)")
            Task { await viewModel.saveLastSessionVideoToPhotos() }
        } label: {
            Group {
                switch status {
                case .idle:
                    Image(systemName: "square.and.arrow.down")
                case .saving:
                    ProgressView().tint(.white).scaleEffect(0.7)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .padding(10)
            .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .disabled(status == .saving || status == .saved)
    }

    @ViewBuilder
    private var deepAnalysisOverlayButton: some View {
        switch deepStatus.stage {
        case .idle:
            Button {
                liveViewLog.debug("Deep analysis sparkle tapped: deliveryID=\(deliveryID.uuidString.prefix(8), privacy: .public)")
                Task { await viewModel.runDeepAnalysisIfNeeded(for: deliveryID) }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(peacockBlue.opacity(0.85)))
            }
        case .running:
            ProgressView().tint(peacockBlue).scaleEffect(0.9)
                .padding(12)
                .background(Circle().fill(Color.black.opacity(0.45)))
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
                .padding(12)
                .background(Circle().fill(Color.black.opacity(0.45)))
        case .failed:
            Button {
                liveViewLog.debug("Deep analysis retry tapped: deliveryID=\(deliveryID.uuidString.prefix(8), privacy: .public)")
                Task { await viewModel.runDeepAnalysisIfNeeded(for: deliveryID) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
        }
    }

    // MARK: - Video Overlay Chips (bottom 15%)

    private static let speedOptions: [(label: String, rate: Float)] = [
        ("0.25×", 0.25), ("0.5×", 0.5), ("1×", 1.0)
    ]

    private var videoOverlayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                // Speed chips: 0.25×, 0.5×, 1×
                ForEach(Self.speedOptions, id: \.rate) { option in
                    let isActive = !isPlaybackPaused && playbackRate == option.rate
                    Button {
                        liveViewLog.debug("Speed chip tapped: rate=\(option.rate)")
                        isPlaybackPaused = false
                        playbackRate = option.rate
                        applyPlaybackMode()
                    } label: {
                        Text(option.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isActive ? .black : .white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(isActive ? peacockBlue : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Pause / Play
                Button {
                    liveViewLog.debug("Overlay pause chip tapped: paused=\(isPlaybackPaused)")
                    togglePause()
                } label: {
                    Image(systemName: isPlaybackPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isPlaybackPaused ? .black : .white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(isPlaybackPaused ? .orange : Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 16)

                // Phase focus chips (ordered by timestamp)
                ForEach(focusSuggestions) { suggestion in
                    let isActive = selectedFocusChipID == suggestion.id
                    Button {
                        toggleFocusSuggestion(suggestion)
                    } label: {
                        Text(suggestion.phaseName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isActive ? .black : .white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(isActive ? peacockBlue : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Detail Page (swipe down)

    private var detailPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let delivery {
                deepAnalysisStatusSection(for: delivery)
            }
            phaseAnalysisSection
            if let delivery {
                dnaSection(for: delivery)
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
                        liveViewLog.debug("Run Deep Analysis tapped: deliveryID=\(deliveryID.uuidString, privacy: .public)")
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
                        liveViewLog.debug("Retry Deep Analysis tapped: deliveryID=\(deliveryID.uuidString, privacy: .public)")
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
            SessionDNAMatchCarousel(matches: matches, userDNA: delivery.dna)
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

    // poseNote kept as internal state for logging; removed from UI display

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
        liveViewLog.debug("refreshArtifacts: deliveryID=\(self.deliveryID.uuidString.prefix(8), privacy: .public), phases=\(self.phases.count), deepStatus=\(String(describing: self.deepStatus.stage), privacy: .public)")
        guard let artifacts = viewModel.deepAnalysisArtifacts(for: deliveryID) else {
            liveViewLog.debug("refreshArtifacts: no artifacts for delivery \(self.deliveryID.uuidString.prefix(8), privacy: .public), phases=\(self.phases.count)")
            if phases.isEmpty {
                poseNote = "Run Deep Analysis to generate pose annotation."
            } else {
                // Deep analysis completed but no artifacts found — likely ID mismatch
                poseNote = "Pose data not linked. Re-run deep analysis."
                liveViewLog.warning("Phases exist (\(self.phases.count)) but no artifacts for deliveryID=\(self.deliveryID.uuidString.prefix(8), privacy: .public). Available artifact keys: \(self.viewModel.deepAnalysisArtifactsByDelivery.keys.map { $0.uuidString.prefix(8) }, privacy: .public)")
                expertAnalysis = ExpertAnalysisBuilder.build(from: phases)
            }
            rebuildSyncControllerIfPossible()
            return
        }

        liveViewLog.info("refreshArtifacts: delivery \(self.deliveryID.uuidString.prefix(8), privacy: .public) — poseFrames=\(artifacts.poseFrames.count), hasExpertAnalysis=\(artifacts.expertAnalysis != nil)")

        if !artifacts.poseFrames.isEmpty {
            poseFrames = artifacts.poseFrames
            poseNote = "Pose overlay generated from local MediaPipe extraction."
            liveViewLog.debug("Pose frames loaded: \(artifacts.poseFrames.count) frames")
        } else if deepStatus.stage == .ready {
            poseNote = artifacts.poseFailureReason ?? "Pose overlay unavailable for this delivery."
            liveViewLog.warning("Deep analysis ready but 0 pose frames for delivery \(self.deliveryID.uuidString.prefix(8), privacy: .public). reason=\(artifacts.poseFailureReason ?? "-", privacy: .public)")
        }

        if let analysis = artifacts.expertAnalysis {
            expertAnalysis = analysis
            liveViewLog.debug("Expert analysis loaded: \(analysis.phases.count) phases")
        } else {
            expertAnalysis = ExpertAnalysisBuilder.build(from: phases)
            liveViewLog.debug("Expert analysis built from delivery phases: \(self.phases.count) phases")
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
        liveViewLog.debug("Focus chip selected: phase=\(suggestion.phaseName, privacy: .public), window=\(window.lowerBound, privacy: .public)-\(window.upperBound, privacy: .public)")
        seek(to: window.lowerBound)
        applyPlaybackMode()
        startFocusLoop()
    }

    private func clearFocusLoop() {
        selectedFocusChipID = nil
        focusWindow = nil
        focusLoopTask?.cancel()
        focusLoopTask = nil
        liveViewLog.debug("Focus loop cleared for deliveryID=\(deliveryID.uuidString, privacy: .public)")
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
        liveViewLog.debug("Pause toggled: isPaused=\(isPlaybackPaused)")
        if isPlaybackPaused {
            focusLoopTask?.cancel()
        } else if focusWindow != nil {
            startFocusLoop()
        }
        applyPlaybackMode()
    }


    private func applyPlaybackMode() {
        guard let player else { return }
        if isPlaybackPaused {
            player.pause()
            return
        }
        player.playImmediately(atRate: playbackRate)
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

    /// Execute a playback command from the review agent.
    private func executePlaybackCommand(_ cmd: SessionViewModel.PlaybackCommand) {
        guard let player else { return }
        liveViewLog.debug("Agent playback command: \(cmd.action.rawValue), ts=\(cmd.timestamp ?? -1), rate=\(cmd.rate ?? -1)")

        switch cmd.action {
        case .play:
            isPlaybackPaused = false
            playbackRate = cmd.rate ?? 1.0
            applyPlaybackMode()

        case .pause:
            isPlaybackPaused = true
            applyPlaybackMode()

        case .slowMo:
            isPlaybackPaused = false
            playbackRate = cmd.rate ?? 0.25
            applyPlaybackMode()

        case .seek:
            if let ts = cmd.timestamp {
                isPlaybackPaused = false
                seek(to: ts)
                applyPlaybackMode()
            }

        case .focusPhase:
            if let ts = cmd.timestamp {
                isPlaybackPaused = false
                playbackRate = cmd.rate ?? 0.5
                let window = SessionResultsPlanner.focusWindow(
                    for: ts,
                    clipDuration: clipDurationSeconds
                )
                focusWindow = window
                seek(to: window.lowerBound)
                applyPlaybackMode()
                startFocusLoop()
            }
        }
    }

    private func rebuildSyncControllerIfPossible() {
        guard let player, !poseFrames.isEmpty else {
            liveViewLog.debug("rebuildSyncController skipped: hasPlayer=\(self.player != nil), poseFrames=\(self.poseFrames.count)")
            return
        }
        syncController?.cleanup()
        syncController = SkeletonSyncController(
            player: player,
            frames: poseFrames,
            expertAnalysis: expertAnalysis
        )
        liveViewLog.info("Skeleton sync controller rebuilt: frames=\(self.poseFrames.count), hasExpertAnalysis=\(self.expertAnalysis != nil)")
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

}

private struct SessionDeliveryClipCard: View {
    let delivery: Delivery
    let player: AVQueuePlayer?
    let syncController: SkeletonSyncController?
    let isPoseLoading: Bool

    var body: some View {
        ZStack {
            Group {
                if let player {
                    CustomVideoPlayer(player: player)
                } else if delivery.videoURL != nil {
                    Color.black
                        .overlay { ProgressView().tint(.white) }
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
                    .onAppear {
                        liveViewLog.info("SessionDeliveryClipCard: skeleton overlay VISIBLE for delivery #\(delivery.sequence)")
                    }
            }
        }
    }
}

private struct FinePrintOverlayLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(text: "Injury risk", color: .red)
            legendItem(text: "Good", color: .green)
            legendItem(text: "Attention", color: .yellow)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private func legendItem(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .shadow(color: color.opacity(0.6), radius: 3)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
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

private struct SessionDNAMatchCarousel: View {
    let matches: [BowlingDNAMatch]
    let userDNA: BowlingDNA?

    @State private var showComparison = false

    private var match: BowlingDNAMatch? { matches.first }

    private var ringColor: Color {
        guard let pct = match?.similarityPercent else { return peacockBlue }
        if pct >= 70 { return Color(hex: "34C759") }
        if pct >= 45 { return peacockBlue }
        return Color(hex: "FF8A3D")
    }

    var body: some View {
        if let match {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("YOUR ACTION ARCHETYPE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(peacockBlue.opacity(0.8))
                    Spacer()
                    if userDNA != nil {
                        Text("Compare")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(peacockBlue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(peacockBlue.opacity(0.6))
                    }
                }
                .padding(.bottom, 14)

                // Hero row: ring + name
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 5)
                            .frame(width: 68, height: 68)
                        Circle()
                            .trim(from: 0, to: CGFloat(match.similarityPercent / 100.0))
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 68, height: 68)
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int(match.similarityPercent))")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.bowlerName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(countryFlag(match.country)) \(match.country) • \(match.era)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        Text(match.style)
                            .font(.system(size: 11))
                            .foregroundColor(peacockBlue)
                    }
                    Spacer()
                }
                .padding(.bottom, 14)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.bottom, 12)

                // Phase match + difference
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "34C759"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Closest")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                            Text(match.closestPhase)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FF8A3D"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Work on")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                            Text(match.biggestDifference)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 12)

                // Signature traits
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(match.signatureTraits, id: \.self) { trait in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(peacockBlue.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(trait)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ringColor.opacity(0.25), lineWidth: 1)
            )
            .onTapGesture {
                if userDNA != nil { showComparison = true }
            }
            .fullScreenCover(isPresented: $showComparison) {
                if let dna = userDNA {
                    DNAComparisonSheet(userDNA: dna, match: match)
                }
            }
        }
    }

    private func countryFlag(_ code: String) -> String {
        switch code {
        case "AUS": return "🇦🇺"
        case "PAK": return "🇵🇰"
        case "IND": return "🇮🇳"
        case "ENG": return "🇬🇧"
        case "SL":  return "🇱🇰"
        case "SA":  return "🇿🇦"
        case "WI":  return "🏴‍☠️"
        default:    return "🏏"
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

// MARK: - Speed Badge

private struct SessionSpeedBadge: View {
    let kph: Double
    let errorMarginKph: Double?

    private var speedText: String {
        if let margin = errorMarginKph {
            return "\(String(format: "%.0f", kph)) ±\(String(format: "%.0f", margin)) kph"
        }
        return "~\(String(format: "%.0f", kph)) kph"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.needle.fill")
                .font(.caption2)
            Text(speedText)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(peacockBlue.opacity(0.85))
                .shadow(color: peacockBlue.opacity(0.4), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - DNA Comparison Full-Screen Sheet

private struct DNAComparisonSheet: View {
    let userDNA: BowlingDNA
    let match: BowlingDNAMatch
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DNAComparisonPage(userDNA: userDNA, match: match)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6), .white.opacity(0.15))
            }
            .padding(.trailing, 16)
            .padding(.top, 12)
        }
        .background(Color(hex: "0D1117"))
    }
}
