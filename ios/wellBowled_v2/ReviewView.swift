import SwiftUI

struct ReviewView: View {
    let delivery: Delivery
    let onSave: (FrameMarkers, Double) -> Void
    let onDismiss: () -> Void

    @StateObject private var extractor: FrameExtractor
    @State private var markers: FrameMarkers
    @State private var distanceMeters: Double
    @State private var distanceDigits: String
    @State private var showDistanceEditor = false
    @State private var activeEditor: EditorTarget
    @State private var markerMessage: String?
    @AppStorage("savedDistance") private var savedDistance: Double = SpeedCalc.defaultDistanceMeters

    private enum EditorTarget {
        case release
        case end
        case distance

        var title: String {
            switch self {
            case .release: return "Release"
            case .end: return "End"
            case .distance: return "Distance"
            }
        }

        var color: Color {
            switch self {
            case .release: return .orange
            case .end: return .green
            case .distance: return Color(red: 0, green: 0.427, blue: 0.467)
            }
        }
    }

    init(delivery: Delivery, onSave: @escaping (FrameMarkers, Double) -> Void, onDismiss: @escaping () -> Void) {
        self.delivery = delivery
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._extractor = StateObject(wrappedValue: FrameExtractor(
            url: delivery.videoURL,
            fps: delivery.fps,
            duration: delivery.duration,
            totalFrames: delivery.totalFrames
        ))

        let initialMarkers = delivery.markers
        let initialDistance = initialMarkers.releaseFrame != nil
            ? delivery.distanceMeters
            : (UserDefaults.standard.double(forKey: "savedDistance").nonZero ?? SpeedCalc.defaultDistanceMeters)

        self._markers = State(initialValue: initialMarkers)
        self._distanceMeters = State(initialValue: initialDistance)
        self._distanceDigits = State(initialValue: Self.digitsText(for: initialDistance))
        self._activeEditor = State(initialValue: initialMarkers.releaseFrame == nil ? .release : (initialMarkers.arrivalFrame == nil ? .end : .distance))
    }

    private var distanceText: String {
        Self.formattedDistanceText(fromDigits: distanceDigits)
    }

    private var speedKMH: Double? {
        guard let releaseFrame = markers.releaseFrame, let endFrame = markers.arrivalFrame else { return nil }
        return SpeedCalc.kmh(releaseFrame: releaseFrame, arrivalFrame: endFrame, fps: delivery.fps, distanceMeters: distanceMeters)
    }

    private var speedMPH: Double? {
        guard let kmh = speedKMH else { return nil }
        return SpeedCalc.mph(kmh: kmh)
    }

    private var speedErrorKMH: Double? {
        guard let releaseFrame = markers.releaseFrame, let endFrame = markers.arrivalFrame else { return nil }
        return SpeedCalc.kmhFrameVariance(releaseFrame: releaseFrame, arrivalFrame: endFrame, fps: delivery.fps, distanceMeters: distanceMeters)
    }

    private var category: SpeedCategory? {
        guard let kmh = speedKMH else { return nil }
        return .from(kmh: kmh)
    }

    private var frameDiff: Int? {
        markers.frameDiff
    }

    private var currentEditor: EditorTarget {
        switch activeEditor {
        case .release:
            return .release
        case .end:
            return markers.releaseFrame == nil ? .release : .end
        case .distance:
            if markers.releaseFrame == nil { return .release }
            if markers.arrivalFrame == nil { return .end }
            return .distance
        }
    }

    private var primaryActionTitle: String {
        switch currentEditor {
        case .release:
            return markers.releaseFrame == nil ? "Set Release Here" : "Move Release Here"
        case .end:
            return markers.arrivalFrame == nil ? "Set End Here" : "Move End Here"
        case .distance:
            return "Edit Distance"
        }
    }

    private var helperText: String {
        switch currentEditor {
        case .release:
            return markers.releaseFrame == nil
                ? "First pass: choose the release frame."
                : "Release can be changed at any time."
        case .end:
            guard let releaseFrame = markers.releaseFrame else {
                return "Set release before choosing the end frame."
            }
            if extractor.currentFrameIndex <= releaseFrame {
                return "End must be after the release frame."
            }
            return markers.arrivalFrame == nil
                ? "First pass: choose the end frame."
                : "End can be changed independently, but must stay after release."
        case .distance:
            return "Distance is independent. Change it anytime and the calculations update immediately."
        }
    }

    private var canApplyCurrentEditor: Bool {
        switch currentEditor {
        case .release:
            return true
        case .end:
            guard let releaseFrame = markers.releaseFrame else { return false }
            return extractor.currentFrameIndex > releaseFrame
        case .distance:
            return true
        }
    }

    private var canFinishReview: Bool {
        !markers.isComplete || distanceMeters > 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                frameView
                controlsView
            }
        }
        .onAppear {
            extractor.loadFirstFrame()
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
            if showDistanceEditor {
                dismissDistanceEditor()
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if let releaseFrame = markers.releaseFrame, extractor.currentFrameIndex == releaseFrame {
                    badge("RELEASE", color: .orange)
                }
                if let endFrame = markers.arrivalFrame, extractor.currentFrameIndex == endFrame {
                    badge("END", color: .green)
                }
            }
            .padding(8)
        }
    }

    private var controlsView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("F\(extractor.currentFrameIndex + 1)/\(extractor.totalFrames)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)

                Text(extractor.currentTimeString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)

                Spacer()

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

            editorControls

            if markers.isComplete {
                speedResultView
            }

            Button {
                persistCurrentSelection()
                onDismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0, green: 0.427, blue: 0.467).opacity(canFinishReview ? 1 : 0.5))
                    .cornerRadius(10)
            }
            .disabled(!canFinishReview)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    private var editorControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                editorChip(
                    title: markers.releaseFrame.map { "Release \($0 + 1)" } ?? "Release",
                    color: .orange,
                    isActive: currentEditor == .release,
                    enabled: true
                ) {
                    selectEditor(.release)
                }

                editorChip(
                    title: markers.arrivalFrame.map { "End \($0 + 1)" } ?? "End",
                    color: .green,
                    isActive: currentEditor == .end,
                    enabled: markers.releaseFrame != nil
                ) {
                    selectEditor(.end)
                }

                editorChip(
                    title: "\(distanceText)m",
                    color: Color(red: 0, green: 0.427, blue: 0.467),
                    isActive: currentEditor == .distance,
                    enabled: markers.isComplete
                ) {
                    selectEditor(.distance)
                }

                if markers.releaseFrame != nil {
                    Menu {
                        if let releaseFrame = markers.releaseFrame {
                            Button("Go to Release") {
                                extractor.seekToFrame(releaseFrame)
                                selectEditor(.release)
                            }
                        }

                        if let endFrame = markers.arrivalFrame {
                            Button("Go to End") {
                                extractor.seekToFrame(endFrame)
                                selectEditor(.end)
                            }
                        }

                        if markers.arrivalFrame != nil {
                            Button("Clear End", role: .destructive) {
                                clearEnd()
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

            Text(markerMessage ?? helperText)
                .font(.system(size: 12))
                .foregroundColor(markerMessage == nil ? .secondary : .orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            Button {
                applyCurrentEditor()
            } label: {
                Text(primaryActionTitle)
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(currentEditor.color.opacity(canApplyCurrentEditor ? 1 : 0.5))
                    .cornerRadius(10)
            }
            .disabled(!canApplyCurrentEditor)
            .padding(.horizontal)
        }
    }

    private var distanceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Distance")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    dismissDistanceEditor()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(distanceText)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("m")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
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

                Text("4 digits. Format is xy.ab")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { digit in
                            keypadButton(title: digit) {
                                appendDistanceDigit(digit)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)

                    keypadButton(title: "0") {
                        appendDistanceDigit("0")
                    }

                    keypadButton(systemName: "delete.left.fill") {
                        deleteDistanceDigit()
                    }
                }
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
    }

    private static let targetKMH: Double = 120.0

    private var targetFrames: Int? {
        guard delivery.fps > 0, distanceMeters > 0 else { return nil }
        let seconds = distanceMeters / (Self.targetKMH / 3.6)
        return Int(ceil(seconds * delivery.fps))
    }

    private var speedResultView: some View {
        VStack(spacing: 8) {
            if let kmh = speedKMH, let category = category {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", kmh))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(category.color)
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
                            .foregroundColor(.white)
                        Text("mph")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text(category.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(category.color)
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
                .background(category.color.opacity(0.1))
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

                VStack(spacing: 4) {
                    Text("Distance \(distanceText)m")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let releaseFrame = markers.releaseFrame, let endFrame = markers.arrivalFrame {
                        Text("Release \(releaseFrame + 1)  End \(endFrame + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
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

    private func editorChip(title: String, color: Color, isActive: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(enabled ? (isActive ? .black : .white) : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(enabled ? (isActive ? color : Color.white.opacity(0.08)) : Color.white.opacity(0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? color.opacity(0.95) : color.opacity(enabled ? 0.35 : 0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.6)
    }

    private func keypadButton(title: String? = nil, systemName: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
        }
    }

    private func selectEditor(_ editor: EditorTarget) {
        markerMessage = nil
        activeEditor = editor

        switch editor {
        case .release:
            dismissDistanceEditor()
            if let releaseFrame = markers.releaseFrame {
                extractor.seekToFrame(releaseFrame)
            }
        case .end:
            dismissDistanceEditor()
            if let endFrame = markers.arrivalFrame {
                extractor.seekToFrame(endFrame)
            } else if let releaseFrame = markers.releaseFrame {
                extractor.seekToFrame(min(releaseFrame + 1, extractor.totalFrames - 1))
            }
        case .distance:
            if markers.isComplete {
                presentDistanceEditor()
            }
        }
    }

    private func applyCurrentEditor() {
        markerMessage = nil

        switch currentEditor {
        case .release:
            let previousEnd = markers.arrivalFrame
            markers.setRelease(extractor.currentFrameIndex)
            if previousEnd != nil, markers.arrivalFrame == nil {
                markerMessage = "End cleared because it must stay after release."
                activeEditor = .end
            } else if markers.arrivalFrame == nil {
                activeEditor = .end
            } else {
                activeEditor = .release
            }
            dismissDistanceEditor()

        case .end:
            let wasUnset = markers.arrivalFrame == nil
            guard markers.setArrival(extractor.currentFrameIndex) else {
                markerMessage = "End must be after the release frame."
                return
            }
            activeEditor = wasUnset ? .distance : .end
            if wasUnset {
                presentDistanceEditor()
            }

        case .distance:
            if markers.isComplete {
                presentDistanceEditor()
            }
        }

        persistCurrentSelection()
    }

    private func clearRelease() {
        markers.clearRelease()
        markerMessage = nil
        activeEditor = .release
        dismissDistanceEditor()
        persistCurrentSelection()
    }

    private func clearEnd() {
        markers.clearArrival()
        markerMessage = nil
        activeEditor = .end
        dismissDistanceEditor()
        persistCurrentSelection()
    }

    private func presentDistanceEditor() {
        showDistanceEditor = true
    }

    private func dismissDistanceEditor() {
        showDistanceEditor = false
    }

    private func appendDistanceDigit(_ digit: String) {
        guard distanceDigits.count < 4 else { return }
        distanceDigits.append(digit)
        syncDistanceFromDigits()
    }

    private func deleteDistanceDigit() {
        guard !distanceDigits.isEmpty else { return }
        distanceDigits.removeLast()
        syncDistanceFromDigits()
    }

    private func syncDistanceFromDigits() {
        let padded = Self.paddedDigits(from: distanceDigits)
        distanceMeters = (Double(padded) ?? 0) / 100
        persistCurrentSelection()
    }

    private func persistCurrentSelection() {
        onSave(markers, distanceMeters)
    }

    private static func digitsText(for distance: Double) -> String {
        String(format: "%04d", max(0, min(Int((distance * 100).rounded()), 9999)))
    }

    private static func paddedDigits(from digits: String) -> String {
        let sanitized = String(digits.filter(\.isNumber).prefix(4))
        return String(repeating: "0", count: max(0, 4 - sanitized.count)) + sanitized
    }

    private static func formattedDistanceText(fromDigits digits: String) -> String {
        let padded = paddedDigits(from: digits)
        let whole = String(padded.prefix(2))
        let fraction = String(padded.suffix(2))
        return "\(whole).\(fraction)"
    }
}
