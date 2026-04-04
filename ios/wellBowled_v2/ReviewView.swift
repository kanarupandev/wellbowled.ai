import SwiftUI

struct ReviewView: View {
    let delivery: Delivery
    let onSave: (Int, Int, Double) -> Void   // (releaseFrame, arrivalFrame, distanceMeters)
    let onDismiss: () -> Void

    @StateObject private var extractor: FrameExtractor
    @State private var releaseFrame: Int?
    @State private var arrivalFrame: Int?
    @State private var distanceMeters: Double
    @State private var distanceText: String
    @State private var showDistanceEditor = false
    @State private var clipSaveState: ClipSaveState = .idle
    @FocusState private var distanceFieldFocused: Bool
    @AppStorage("savedDistance") private var savedDistance: Double = SpeedCalc.defaultDistanceMeters

    private enum ClipSaveState { case idle, saving, saved, failed(String) }

    init(delivery: Delivery, onSave: @escaping (Int, Int, Double) -> Void, onDismiss: @escaping () -> Void) {
        self.delivery = delivery
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._extractor = StateObject(wrappedValue: FrameExtractor(
            url: delivery.videoURL, fps: delivery.fps,
            duration: delivery.duration, totalFrames: delivery.totalFrames
        ))
        self._releaseFrame = State(initialValue: delivery.releaseFrame)
        self._arrivalFrame = State(initialValue: delivery.arrivalFrame)
        // Use saved distance for new deliveries, keep existing for re-reviews
        let dist = delivery.releaseFrame != nil ? delivery.distanceMeters :
            UserDefaults.standard.double(forKey: "savedDistance").nonZero ?? SpeedCalc.defaultDistanceMeters
        self._distanceMeters = State(initialValue: dist)
        self._distanceText = State(initialValue: Self.formattedDistanceText(for: dist))
    }

    private var step: Step {
        if releaseFrame != nil && arrivalFrame != nil { return .done }
        if releaseFrame != nil { return .pickArrival }
        return .scrubbing
    }

    private enum Step { case scrubbing, pickArrival, done }

    // Speed computed from local state using shared SpeedCalc
    private var speedKMH: Double? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return SpeedCalc.kmh(releaseFrame: r, arrivalFrame: a, fps: delivery.fps, distanceMeters: distanceMeters)
    }

    private var speedMPH: Double? {
        guard let kmh = speedKMH else { return nil }
        return SpeedCalc.mph(kmh: kmh)
    }

    private var category: SpeedCategory? {
        guard let kmh = speedKMH else { return nil }
        return .from(kmh: kmh)
    }

    private var frameDiff: Int? {
        guard let r = releaseFrame, let a = arrivalFrame else { return nil }
        return a - r
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                frameView
                controlsView
            }
        }
        .onAppear { extractor.loadFirstFrame() }
        .onChange(of: distanceFieldFocused) { focused in
            if !focused {
                showDistanceEditor = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissDistanceEditor()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showDistanceEditor {
                distanceEditor
            }
        }
    }

    // MARK: - Frame View

    private var frameView: some View {
        Group {
            if let image = extractor.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissDistanceEditor()
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if let r = releaseFrame, extractor.currentFrameIndex == r {
                    badge("RELEASE", color: .orange)
                }
                if let a = arrivalFrame, extractor.currentFrameIndex == a {
                    badge("ARRIVAL", color: .green)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 10) {
            // Distance + frame info
            HStack(spacing: 8) {
                Image(systemName: "ruler")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    presentDistanceEditor()
                } label: {
                    Text(distanceText)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(minWidth: 92)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(showDistanceEditor ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                }
                Text("m")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                // Save as default button
                Button {
                    savedDistance = distanceMeters
                } label: {
                    Image(systemName: distanceMeters == savedDistance ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(distanceMeters == savedDistance ? .green : .secondary)
                }

                Spacer()

                Text("F\(extractor.currentFrameIndex + 1)/\(extractor.totalFrames)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)

                Text(extractor.currentTimeString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)

                Text("\(Int(delivery.fps))fps")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Scrubber
            HStack(spacing: 16) {
                Button { extractor.advance(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                }
                Button { extractor.previousFrame() } label: {
                    Image(systemName: "chevron.left").font(.title3.bold())
                }

                Slider(
                    value: Binding(
                        get: { Double(extractor.currentFrameIndex) },
                        set: { extractor.seekToFrame(Int($0)) }
                    ),
                    in: 0...Double(max(1, extractor.totalFrames - 1)),
                    step: 1
                )

                Button { extractor.nextFrame() } label: {
                    Image(systemName: "chevron.right").font(.title3.bold())
                }
                Button { extractor.advance(by: 10) } label: {
                    Image(systemName: "goforward.10")
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal)

            // Action area
            switch step {
            case .scrubbing:
                actionButton("Mark Release Frame", color: .orange) {
                    releaseFrame = extractor.currentFrameIndex
                }

            case .pickArrival:
                VStack(spacing: 8) {
                    HStack {
                        badge("Release @ \(releaseFrame! + 1)", color: .orange)
                        Spacer()
                        Button("Reset") {
                            releaseFrame = nil
                            arrivalFrame = nil
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)

                    actionButton("Mark Arrival Frame", color: .green) {
                        arrivalFrame = extractor.currentFrameIndex
                        // Save back to parent
                        if let r = releaseFrame, let a = arrivalFrame {
                            onSave(r, a, distanceMeters)
                        }
                    }
                }

            case .done:
                speedResultView
            }

            // Save + Done
            saveAndDoneButtons
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    private var distanceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distance to impact")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            HStack(alignment: .center, spacing: 10) {
                TextField("17.68", text: Binding(
                    get: { distanceText },
                    set: { applyDistanceInput($0) }
                ))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .keyboardType(.numberPad)
                    .focused($distanceFieldFocused)
                    .frame(width: 150)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)

                Text("m")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    dismissDistanceEditor()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(12)
                }
            }

            HStack(spacing: 10) {
                Button {
                    savedDistance = distanceMeters
                } label: {
                    Label(
                        distanceMeters == savedDistance ? "Saved default" : "Save as default",
                        systemImage: distanceMeters == savedDistance ? "checkmark.circle.fill" : "checkmark.circle"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(distanceMeters == savedDistance ? .green : .white)
                }

                Spacer()

                Text("4 digits only. Dot is inserted automatically.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            DispatchQueue.main.async {
                distanceFieldFocused = true
            }
        }
    }

    // MARK: - Speed Result

    // Target speed baked in
    private static let targetKMH: Double = 120.0

    private var targetFrames: Int? {
        guard delivery.fps > 0, distanceMeters > 0 else { return nil }
        let seconds = distanceMeters / (Self.targetKMH / 3.6)
        return Int(ceil(seconds * delivery.fps))
    }

    private var speedResultView: some View {
        VStack(spacing: 8) {
            if let kmh = speedKMH, let cat = category {
                // Main speed display
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", kmh))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(cat.color)
                        Text("km/h")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", speedMPH ?? 0))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        Text("mph")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text(cat.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(cat.color)
                        Text("\(frameDiff ?? 0) frames")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(Int(delivery.fps)) fps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal)
                .background(cat.color.opacity(0.1))
                .cornerRadius(12)

                // Target comparison
                if let target = targetFrames, let diff = frameDiff {
                    HStack(spacing: 6) {
                        Image(systemName: diff <= target ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .foregroundColor(diff <= target ? .green : .orange)
                            .font(.caption)
                        Text("Target: \(target) frames (\(Int(Self.targetKMH)) km/h)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        if diff > target {
                            Text("need \(diff - target) fewer")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                        } else {
                            Text("hit!")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal)
                }

                // Frame markers + redo
                HStack(spacing: 12) {
                    Button { extractor.seekToFrame(releaseFrame!) } label: {
                        badge("Release @ \(releaseFrame! + 1)", color: .orange)
                    }
                    Button { extractor.seekToFrame(arrivalFrame!) } label: {
                        badge("Arrival @ \(arrivalFrame! + 1)", color: .green)
                    }
                    Spacer()
                    Button("Redo") {
                        releaseFrame = nil
                        arrivalFrame = nil
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Save & Done

    private var saveAndDoneButtons: some View {
        VStack(spacing: 8) {
            // Save options row
            if step == .done {
                HStack(spacing: 10) {
                    Button {
                        saveClip(kind: .releaseToEnd)
                    } label: {
                        saveLabel("Clip & Save", icon: "scissors")
                    }

                    Button {
                        saveClip(kind: .full)
                    } label: {
                        saveLabel("Save Full", icon: "film")
                    }
                }
                .disabled(isSaving)

                if case .saved = clipSaveState {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to Photos & Clips")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                if case .failed(let msg) = clipSaveState {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Done button
            Button {
                dismissDistanceEditor()
                if let r = releaseFrame, let a = arrivalFrame {
                    onSave(r, a, distanceMeters)
                }
                onDismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0, green: 0.427, blue: 0.467))
                    .cornerRadius(10)
            }
        }
    }

    private var isSaving: Bool {
        if case .saving = clipSaveState { return true }
        return false
    }

    private func saveLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            if isSaving {
                ProgressView().tint(.white).scaleEffect(0.7)
            } else {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func saveClip(kind: SavedClip.ClipKind) {
        guard !isSaving else { return }
        // Build a delivery with current state
        var d = delivery
        d.releaseFrame = releaseFrame
        d.arrivalFrame = arrivalFrame
        d.distanceMeters = distanceMeters

        clipSaveState = .saving
        Task {
            do {
                switch kind {
                case .releaseToEnd:
                    _ = try await ClipStore.shared.saveReleaseClip(from: delivery.videoURL, delivery: d)
                case .full:
                    _ = try await ClipStore.shared.saveFullVideo(from: delivery.videoURL, delivery: d)
                }
                await MainActor.run { clipSaveState = .saved }
            } catch {
                await MainActor.run { clipSaveState = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: - Helpers

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color)
                .cornerRadius(10)
        }
        .padding(.horizontal)
    }

    private func presentDistanceEditor() {
        showDistanceEditor = true
        DispatchQueue.main.async {
            distanceFieldFocused = true
        }
    }

    private func dismissDistanceEditor() {
        distanceFieldFocused = false
        showDistanceEditor = false
    }

    private func applyDistanceInput(_ rawValue: String) {
        let digits = String(rawValue.filter(\.isNumber).prefix(4))
        let formatted = Self.formattedDistanceText(fromDigits: digits)
        if distanceText != formatted {
            distanceText = formatted
        }
        if let value = Double(formatted), value > 0 {
            distanceMeters = value
        }
    }

    private static func formattedDistanceText(for distance: Double) -> String {
        let scaled = max(0, min(Int((distance * 100).rounded()), 9999))
        return formattedDistanceText(fromDigits: String(format: "%04d", scaled))
    }

    private static func formattedDistanceText(fromDigits digits: String) -> String {
        let sanitized = String(digits.filter(\.isNumber).prefix(4))
        let padded = String(repeating: "0", count: max(0, 4 - sanitized.count)) + sanitized
        let whole = String(padded.prefix(2))
        let fraction = String(padded.suffix(2))
        return "\(whole).\(fraction)"
    }
}
