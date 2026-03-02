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
            SessionResultsView(session: viewModel.session)
        }
        .onChange(of: viewModel.session.isActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            if viewModel.session.deliveryCount > 0 && !viewModel.isAnalyzing {
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
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section("Session") {
                    HStack {
                        Text("Deliveries")
                        Spacer()
                        Text("\(session.deliveryCount)")
                            .foregroundColor(peacockBlue)
                            .bold()
                    }
                    if session.duration > 0 {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(formatDuration(session.duration))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let summary = session.summary {
                        HStack {
                            Text("Dominant Pace")
                            Spacer()
                            Text(summary.dominantPace.label)
                                .foregroundColor(peacockBlue)
                        }
                        if !summary.keyObservation.isEmpty {
                            Text(summary.keyObservation)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        if let challengeScore = summary.challengeScore {
                            HStack {
                                Text("Challenge")
                                Spacer()
                                Text(challengeScore)
                                    .foregroundColor(peacockBlue)
                                    .bold()
                            }
                        }
                    }
                }

                // BowlingDNA section — show first delivery's top matches (aggregated view)
                if let firstDNA = session.deliveries.first(where: { $0.dnaMatches != nil }),
                   let matches = firstDNA.dnaMatches, !matches.isEmpty {
                    BowlingDNASection(matches: matches)
                }

                // Delivery cards
                Section("Deliveries") {
                    ForEach(session.deliveries, id: \.id) { delivery in
                        DeliveryRow(delivery: delivery)
                    }
                }
            }
            .navigationTitle("Session Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

struct DeliveryRow: View {
    let delivery: Delivery

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(delivery.sequence)")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(peacockBlue)

                if let speed = delivery.speed {
                    Text(speed)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusBadge
            }

            if let report = delivery.report, !report.isEmpty {
                Text(report)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch delivery.status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(peacockBlue)
        case .analyzing:
            ProgressView()
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        default:
            Image(systemName: "clock")
                .foregroundColor(.gray)
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
