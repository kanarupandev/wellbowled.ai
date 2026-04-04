import SwiftUI

struct ReviewView: View {
    let delivery: Delivery
    let onSave: (Int, Int, Double) -> Void
    let onDismiss: () -> Void

    @StateObject private var extractor: FrameExtractor
    @State private var draft: ReviewDraft
    @State private var distanceInput: DistanceInput
    @State private var showDistanceEditor = false
    @State private var replaceDistanceOnNextDigit = false
    @State private var clipSaveState: ClipSaveState = .idle
    @State private var dragStartFrame: Int?
    @AppStorage("savedDistance") private var savedDistance: Double = SpeedCalc.defaultDistanceMeters
    @AppStorage("goalSpeedKMH") private var goalSpeedKMH: Double = SpeedCalc.defaultGoalSpeedKMH

    private enum ClipSaveState {
        case idle
        case saving
        case saved
        case failed(String)
    }

    init(delivery: Delivery, onSave: @escaping (Int, Int, Double) -> Void, onDismiss: @escaping () -> Void) {
        self.delivery = delivery
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._extractor = StateObject(wrappedValue: FrameExtractor(
            url: delivery.videoURL,
            fps: delivery.fps,
            duration: delivery.duration,
            totalFrames: delivery.totalFrames
        ))

        let saved = FrameMarkerStore.shared.lookup(videoURL: delivery.videoURL)
        let release = delivery.releaseFrame ?? saved?.releaseFrame
        let arrival = delivery.arrivalFrame ?? saved?.arrivalFrame
        let distance: Double
        if delivery.releaseFrame != nil || delivery.arrivalFrame != nil {
            distance = delivery.distanceMeters
        } else if let savedDistance = saved?.distanceMeters {
            distance = savedDistance
        } else {
            distance = UserDefaults.standard.double(forKey: "savedDistance").nonZero ?? SpeedCalc.defaultDistanceMeters
        }

        let initialDraft = ReviewDraft(releaseFrame: release, arrivalFrame: arrival, distanceMeters: distance)
        var initialInput = DistanceInput()
        initialInput.replace(with: distance)

        self._draft = State(initialValue: initialDraft)
        self._distanceInput = State(initialValue: initialInput)
    }

    private var speedKMH: Double? {
        guard let release = draft.releaseFrame, let arrival = draft.arrivalFrame else { return nil }
        return SpeedCalc.kmh(
            releaseFrame: release,
            arrivalFrame: arrival,
            fps: delivery.fps,
            distanceMeters: draft.distanceMeters
        )
    }

    private var speedVarianceKMH: Double? {
        guard let release = draft.releaseFrame, let arrival = draft.arrivalFrame else { return nil }
        return SpeedCalc.kmhFrameVariance(
            releaseFrame: release,
            arrivalFrame: arrival,
            fps: delivery.fps,
            distanceMeters: draft.distanceMeters
        )
    }

    private var flightTimeText: String? {
        guard let release = draft.releaseFrame, let arrival = draft.arrivalFrame else { return nil }
        return SpeedCalc.formattedFlightTime(releaseFrame: release, arrivalFrame: arrival, fps: delivery.fps)
    }

    private var goalDeltaSeconds: Double? {
        guard let release = draft.releaseFrame, let arrival = draft.arrivalFrame else { return nil }
        return SpeedCalc.goalTimeDeltaSeconds(
            releaseFrame: release,
            arrivalFrame: arrival,
            fps: delivery.fps,
            distanceMeters: draft.distanceMeters,
            goalSpeedKMH: goalSpeedKMH
        )
    }

    private var primaryActionTitle: String? {
        switch draft.activeField {
        case .release:
            return draft.releaseFrame == nil ? "Set Release Here" : "Move Release Here"
        case .arrival:
            return draft.arrivalFrame == nil ? "Set End Here" : "Move End Here"
        case .distance:
            return nil
        }
    }

    private var canApplyCurrentFrame: Bool {
        switch draft.activeField {
        case .release:
            return true
        case .arrival:
            guard let release = draft.releaseFrame else { return false }
            return extractor.currentFrameIndex > release
        case .distance:
            return false
        }
    }

    private var goalDeltaText: String {
        guard let delta = goalDeltaSeconds else { return "Set markers to compare with goal" }
        if abs(delta) < 0.005 {
            return "On goal pace"
        }
        if delta > 0 {
            return "Need \(String(format: "%.2f", delta))s less"
        }
        return "\(String(format: "%.2f", abs(delta)))s quicker than goal"
    }

    private var saveStateMessage: (text: String, color: Color)? {
        switch clipSaveState {
        case .idle, .saving:
            return nil
        case .saved:
            return ("Saved to Photos and Clips", .green)
        case .failed(let message):
            return (message, .red)
        }
    }

    private var isSaving: Bool {
        if case .saving = clipSaveState {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            frameView

            VStack(spacing: 12) {
                topOverlay

                if showDistanceEditor {
                    distanceEditor
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                VStack(spacing: 10) {
                    if draft.isComplete {
                        resultsPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    bottomOverlay
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: draft.isComplete)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: showDistanceEditor)
        .onAppear {
            extractor.loadFirstFrame()
        }
    }

    private var frameView: some View {
        Group {
            if let image = extractor.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
        .onTapGesture {
            dismissDistanceEditor()
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if let release = draft.releaseFrame, extractor.currentFrameIndex == release {
                    badge("RELEASE", color: .orange)
                }
                if let arrival = draft.arrivalFrame, extractor.currentFrameIndex == arrival {
                    badge("END", color: .green)
                }
            }
            .padding(.top, 72)
            .padding(.leading, 12)
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStartFrame == nil {
                    dragStartFrame = extractor.currentFrameIndex
                }
                let origin = dragStartFrame ?? extractor.currentFrameIndex
                let delta = Int((value.translation.width / 8).rounded())
                extractor.seekToFrame(origin + delta)
            }
            .onEnded { _ in
                dragStartFrame = nil
            }
    }

    private var topOverlay: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                openDistanceEditor()
            } label: {
                Text("\(String(format: "%.2f", draft.distanceMeters))m")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(draft.isComplete ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                draft.activeField == .distance && draft.isComplete ? Color(red: 0, green: 0.427, blue: 0.467) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!draft.isComplete)

            Spacer()

            HStack(spacing: 10) {
                Text("F\(extractor.currentFrameIndex + 1)/\(extractor.totalFrames)")
                Text(extractor.currentTimeString)
                Text("\(Int(delivery.fps))fps")
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                markerChip(title: "Release", frame: draft.releaseFrame, color: .orange, isActive: draft.activeField == .release) {
                    draft.select(.release)
                    dismissDistanceEditor()
                    if let release = draft.releaseFrame {
                        extractor.seekToFrame(release)
                    }
                }

                markerChip(title: "End", frame: draft.arrivalFrame, color: .green, isActive: draft.activeField == .arrival, enabled: draft.releaseFrame != nil) {
                    guard draft.releaseFrame != nil else { return }
                    draft.select(.arrival)
                    dismissDistanceEditor()
                    if let arrival = draft.arrivalFrame {
                        extractor.seekToFrame(arrival)
                    } else if let release = draft.releaseFrame {
                        extractor.seekToFrame(min(release + 1, extractor.totalFrames - 1))
                    }
                }

                Menu {
                    if let release = draft.releaseFrame {
                        Button {
                            draft.select(.release)
                            extractor.seekToFrame(release)
                        } label: {
                            Label("Go to Release", systemImage: "arrow.right.circle")
                        }
                        Button(role: .destructive) {
                            draft.clearRelease()
                            dismissDistanceEditor()
                        } label: {
                            Label("Clear Release", systemImage: "xmark.circle")
                        }
                    }

                    if let arrival = draft.arrivalFrame {
                        Button {
                            draft.select(.arrival)
                            extractor.seekToFrame(arrival)
                        } label: {
                            Label("Go to End", systemImage: "arrow.right.circle")
                        }
                        Button(role: .destructive) {
                            draft.clearArrival()
                            dismissDistanceEditor()
                        } label: {
                            Label("Clear End", systemImage: "xmark.circle")
                        }
                    }

                    if draft.isComplete {
                        Button {
                            openDistanceEditor()
                        } label: {
                            Label("Edit Distance", systemImage: "ruler")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }

            if let title = primaryActionTitle {
                Button {
                    applyActiveSelection()
                } label: {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canApplyCurrentFrame ? Color(red: 0.996, green: 0.784, blue: 0.2) : Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(!canApplyCurrentFrame)
            }

            HStack(spacing: 10) {
                seekButton(systemName: "gobackward.10", action: { extractor.advance(by: -10) })
                seekButton(systemName: "chevron.left", action: { extractor.previousFrame() })

                Slider(
                    value: Binding(
                        get: { Double(extractor.currentFrameIndex) },
                        set: { extractor.seekToFrame(Int($0)) }
                    ),
                    in: 0...Double(max(1, extractor.totalFrames - 1)),
                    step: 1
                )
                .tint(Color(red: 0, green: 0.427, blue: 0.467))

                seekButton(systemName: "chevron.right", action: { extractor.nextFrame() })
                seekButton(systemName: "goforward.10", action: { extractor.advance(by: 10) })
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flightTimeText ?? "--.--s")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Time diff")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(speedKMH.map { String(format: "%.1f km/h", $0) } ?? "--.- km/h")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(speedVarianceKMH.map { "±\(String(format: "%.1f", $0)) km/h" } ?? "±--.- km/h")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("Goal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                smallStepperButton(systemName: "minus") {
                    goalSpeedKMH = max(1, goalSpeedKMH - 1)
                }

                Text("\(Int(goalSpeedKMH)) km/h")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 90)

                smallStepperButton(systemName: "plus") {
                    goalSpeedKMH += 1
                }

                Spacer()

                Text(goalDeltaText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(goalDeltaSeconds ?? 0 > 0 ? .orange : .green)
            }

            HStack(spacing: 10) {
                Button {
                    saveClip(kind: .releaseToEnd)
                } label: {
                    actionPill("Clip & Save", icon: "scissors")
                }

                Button {
                    saveClip(kind: .full)
                } label: {
                    actionPill("Save Full", icon: "film")
                }
            }
            .disabled(isSaving)

            HStack(spacing: 10) {
                if let message = saveStateMessage {
                    Text(message.text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(message.color)
                }

                Spacer()

                Button {
                    persistIfComplete()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(red: 0, green: 0.427, blue: 0.467))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var distanceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Distance")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Default") {
                    distanceInput.replace(with: savedDistance)
                    draft.setDistance(savedDistance)
                    persistIfComplete()
                    replaceDistanceOnNextDigit = false
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.996, green: 0.784, blue: 0.2))

                Button("Done") {
                    dismissDistanceEditor()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            }

            Text("\(distanceInput.text)m")
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text(distanceInput.digitCount == 4 ? "4 digits set" : "Clear and type 4 digits: xy.ab")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                keypadRow(["1", "2", "3"])
                keypadRow(["4", "5", "6"])
                keypadRow(["7", "8", "9"])
                HStack(spacing: 8) {
                    keypadControlLabel("Clear") {
                        distanceInput.clear()
                    }
                    keypadDigit("0")
                    keypadControlIcon("delete.left") {
                        distanceInput.backspace()
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func keypadRow(_ digits: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(digits, id: \.self) { digit in
                keypadDigit(digit)
            }
        }
    }

    private func keypadDigit(_ digit: String) -> some View {
        Button {
            if replaceDistanceOnNextDigit {
                distanceInput.clear()
                replaceDistanceOnNextDigit = false
            }
            if distanceInput.append(digit), distanceInput.digitCount == 4 {
                draft.setDistance(distanceInput.value)
                persistIfComplete()
            }
        } label: {
            Text(digit)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func keypadControlLabel(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func keypadControlIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func markerChip(title: String, frame: Int?, color: Color, isActive: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(frame.map { "\(title) F\($0 + 1)" } ?? title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundColor(enabled ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isActive ? color.opacity(0.22) : Color.white.opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? color : Color.white.opacity(0.08), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.55)
    }

    private func seekButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func smallStepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func actionPill(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }

    private func openDistanceEditor() {
        guard draft.isComplete else { return }
        draft.select(.distance)
        distanceInput.replace(with: draft.distanceMeters)
        replaceDistanceOnNextDigit = true
        showDistanceEditor = true
    }

    private func dismissDistanceEditor() {
        showDistanceEditor = false
        replaceDistanceOnNextDigit = false
        distanceInput.replace(with: draft.distanceMeters)
    }

    private func applyActiveSelection() {
        dismissDistanceEditor()

        switch draft.activeField {
        case .release:
            _ = draft.setRelease(extractor.currentFrameIndex)
        case .arrival:
            guard draft.setArrival(extractor.currentFrameIndex) else { return }
        case .distance:
            break
        }

        persistIfComplete()
    }

    private func persistIfComplete() {
        guard let release = draft.releaseFrame, let arrival = draft.arrivalFrame else { return }
        onSave(release, arrival, draft.distanceMeters)
        FrameMarkerStore.shared.save(
            videoURL: delivery.videoURL,
            releaseFrame: release,
            arrivalFrame: arrival,
            distanceMeters: draft.distanceMeters,
            fps: delivery.fps,
            totalFrames: delivery.totalFrames,
            duration: delivery.duration
        )
    }

    private func saveClip(kind: SavedClip.ClipKind) {
        guard !isSaving else { return }
        var updated = delivery
        updated.releaseFrame = draft.releaseFrame
        updated.arrivalFrame = draft.arrivalFrame
        updated.distanceMeters = draft.distanceMeters

        clipSaveState = .saving
        Task {
            do {
                switch kind {
                case .releaseToEnd:
                    _ = try await ClipStore.shared.saveReleaseClip(from: delivery.videoURL, delivery: updated)
                case .full:
                    _ = try await ClipStore.shared.saveFullVideo(from: delivery.videoURL, delivery: updated)
                }
                await MainActor.run { clipSaveState = .saved }
            } catch {
                await MainActor.run { clipSaveState = .failed(error.localizedDescription) }
            }
        }
    }
}
