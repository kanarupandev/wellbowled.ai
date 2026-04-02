import SwiftUI

struct ReviewView: View {
    let delivery: Delivery
    let onSave: (FrameMarkers, Double) -> Void
    let onDismiss: () -> Void

    @StateObject private var extractor: FrameExtractor
    @State private var markers: FrameMarkers
    @State private var distanceMeters: Double
    @State private var distanceText: String
    @State private var showDistanceEditor = false
    @State private var activeTarget: MarkerTarget?
    @State private var markerMessage: String?
    @FocusState private var distanceFieldFocused: Bool
    @AppStorage("savedDistance") private var savedDistance: Double = SpeedCalc.defaultDistanceMeters

    private enum MarkerTarget {
        case release
        case arrival

        var title: String {
            switch self {
            case .release: return "Release"
            case .arrival: return "End"
            }
        }

        var color: Color {
            switch self {
            case .release: return .orange
            case .arrival: return .green
            }
        }
    }

    init(delivery: Delivery, onSave: @escaping (FrameMarkers, Double) -> Void, onDismiss: @escaping () -> Void) {
        self.delivery = delivery
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._extractor = StateObject(wrappedValue: FrameExtractor(
            url: delivery.videoURL, fps: delivery.fps,
            duration: delivery.duration, totalFrames: delivery.totalFrames
        ))
        let initialMarkers = delivery.markers
        self._markers = State(initialValue: initialMarkers)
        let dist = initialMarkers.releaseFrame != nil ? delivery.distanceMeters :
            UserDefaults.standard.double(forKey: "savedDistance").nonZero ?? SpeedCalc.defaultDistanceMeters
        self._distanceMeters = State(initialValue: dist)
        self._distanceText = State(initialValue: Self.formattedDistanceText(for: dist))
        self._activeTarget = State(initialValue: initialMarkers.releaseFrame == nil ? .release : (initialMarkers.arrivalFrame == nil ? .arrival : nil))
    }

    private var speedKMH: Double? {
        guard let r = markers.releaseFrame, let a = markers.arrivalFrame else { return nil }
        return SpeedCalc.kmh(releaseFrame: r, arrivalFrame: a, fps: delivery.fps, distanceMeters: distanceMeters)
    }

    private var speedMPH: Double? {
        guard let kmh = speedKMH else { return nil }
        return SpeedCalc.mph(kmh: kmh)
    }

    private var speedErrorKMH: Double? {
        guard let r = markers.releaseFrame, let a = markers.arrivalFrame else { return nil }
        return SpeedCalc.kmhFrameVariance(releaseFrame: r, arrivalFrame: a, fps: delivery.fps, distanceMeters: distanceMeters)
    }

    private var category: SpeedCategory? {
        guard let kmh = speedKMH else { return nil }
        return .from(kmh: kmh)
    }

    private var frameDiff: Int? {
        markers.frameDiff
    }

    private var currentTarget: MarkerTarget? {
        activeTarget ?? defaultTarget
    }

    private var defaultTarget: MarkerTarget? {
        if markers.releaseFrame == nil { return .release }
        if markers.arrivalFrame == nil { return .arrival }
        return nil
    }

    private var primaryActionTitle: String? {
        guard let currentTarget else { return nil }
        switch currentTarget {
        case .release:
            return markers.releaseFrame == nil ? "Mark Release Frame" : "Move Release Frame"
        case .arrival:
            return markers.arrivalFrame == nil ? "Mark End Frame" : "Move End Frame"
        }
    }

    private var primaryActionColor: Color {
        currentTarget?.color ?? .white
    }

    private var markerHint: String {
        switch currentTarget {
        case .release:
            return "Scrub to the exact release frame, then tap below."
        case .arrival:
            if let releaseFrame = markers.releaseFrame,
               extractor.currentFrameIndex <= releaseFrame {
                return "End must be after the release frame."
            }
            return "Scrub to the end frame, then tap below."
        case nil:
            return "Distance/results are live. Jump to a marker to adjust it."
        }
    }

    private var canApplyCurrentTarget: Bool {
        guard let currentTarget else { return false }
        switch currentTarget {
        case .release:
            return true
        case .arrival:
            guard let releaseFrame = markers.releaseFrame else { return false }
            return extractor.currentFrameIndex > releaseFrame
        }
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
        .onChange(of: distanceFieldFocused) { _, focused in
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
                if let releaseFrame = markers.releaseFrame,
                   extractor.currentFrameIndex == releaseFrame {
                    badge("RELEASE", color: .orange)
                }
                if let arrivalFrame = markers.arrivalFrame,
                   extractor.currentFrameIndex == arrivalFrame {
                    badge("END", color: .green)
                }
            }
            .padding(8)
        }
    }

    private var controlsView: some View {
        VStack(spacing: 10) {
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

            markerControls

            if markers.isComplete {
                speedResultView
            }

            Button {
                dismissDistanceEditor()
                persistCurrentSelection()
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
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    private var markerControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                markerJumpButton(title: markers.releaseFrame.map { "Release @ \($0 + 1)" } ?? "Release not set", color: .orange, frame: markers.releaseFrame, isActive: currentTarget == .release)
                markerJumpButton(title: markers.arrivalFrame.map { "End @ \($0 + 1)" } ?? "End not set", color: .green, frame: markers.arrivalFrame, isActive: currentTarget == .arrival)

                if markers.releaseFrame != nil {
                    Menu {
                        Button("Adjust Release") {
                            selectTarget(.release)
                        }

                        if markers.releaseFrame != nil {
                            Button(markers.arrivalFrame == nil ? "Set End" : "Adjust End") {
                                selectTarget(.arrival)
                            }
                        }

                        if markers.arrivalFrame != nil {
                            Button("Clear End", role: .destructive) {
                                clearArrival()
                            }
                        }

                        Button(markers.arrivalFrame == nil ? "Clear Release" : "Reset All", role: .destructive) {
                            clearRelease()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal)

            Text(markerMessage ?? markerHint)
                .font(.system(size: 12))
                .foregroundColor(markerMessage == nil ? .secondary : .orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let title = primaryActionTitle {
                actionButton(title, color: primaryActionColor, disabled: !canApplyCurrentTarget) {
                    applyCurrentTarget()
                }
            }
        }
    }

    private var distanceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distance to impact")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            HStack(alignment: .center, spacing: 10) {
                TextField("18.90", text: Binding(
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

    private static let targetKMH: Double = 120.0

    private var targetFrames: Int? {
        guard delivery.fps > 0, distanceMeters > 0 else { return nil }
        let seconds = distanceMeters / (Self.targetKMH / 3.6)
        return Int(ceil(seconds * delivery.fps))
    }

    private var speedResultView: some View {
        VStack(spacing: 8) {
            if let kmh = speedKMH, let cat = category {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", kmh))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(cat.color)
                        if let error = speedErrorKMH {
                            Text("±\(String(format: "%.1f", error)) km/h")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Text("frame-pick variance")
                            .font(.system(size: 10))
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
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }

    private func markerJumpButton(title: String, color: Color, frame: Int?, isActive: Bool) -> some View {
        Button {
            if let frame {
                extractor.seekToFrame(frame)
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(frame == nil ? .secondary : .black)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(frame == nil ? Color.white.opacity(0.08) : color)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(frame == nil)
        .opacity(frame == nil ? 0.7 : 1.0)
    }

    private func actionButton(_ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color.opacity(disabled ? 0.5 : 1.0))
                .cornerRadius(10)
        }
        .disabled(disabled)
        .padding(.horizontal)
    }

    private func selectTarget(_ target: MarkerTarget) {
        dismissDistanceEditor()
        markerMessage = nil
        activeTarget = target
    }

    private func applyCurrentTarget() {
        guard let currentTarget else { return }
        markerMessage = nil

        switch currentTarget {
        case .release:
            let previousArrival = markers.arrivalFrame
            markers.setRelease(extractor.currentFrameIndex)
            if previousArrival != nil, markers.arrivalFrame == nil {
                markerMessage = "End cleared because it must stay after release."
                activeTarget = .arrival
            } else {
                activeTarget = markers.arrivalFrame == nil ? .arrival : nil
            }
        case .arrival:
            guard markers.setArrival(extractor.currentFrameIndex) else {
                markerMessage = "End must be after the release frame."
                return
            }
            activeTarget = nil
            presentDistanceEditor()
        }

        persistCurrentSelection()
    }

    private func clearRelease() {
        markers.clearRelease()
        markerMessage = nil
        activeTarget = .release
        persistCurrentSelection()
    }

    private func clearArrival() {
        markers.clearArrival()
        markerMessage = nil
        activeTarget = .arrival
        persistCurrentSelection()
    }

    private func persistCurrentSelection() {
        onSave(markers, distanceMeters)
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
            persistCurrentSelection()
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
