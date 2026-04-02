import SwiftUI

struct ReviewView: View {
    @ObservedObject var session: BowlSession
    @Binding var delivery: Delivery
    @StateObject private var extractor: FrameExtractor
    @Environment(\.dismiss) var dismiss

    @State private var activePhase: DeliveryPhase? = nil
    @State private var measureMode = false
    @State private var calibrateMode = false
    @State private var measurePoint1: CGPoint?
    @State private var frameSize: CGSize = .zero

    init(session: BowlSession, delivery: Binding<Delivery>) {
        self._session = ObservedObject(wrappedValue: session)
        self._delivery = delivery
        let d = delivery.wrappedValue
        self._extractor = StateObject(wrappedValue: FrameExtractor(
            url: d.videoURL, fps: d.fps, duration: d.duration, totalFrames: d.totalFrames
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Frame display with annotation overlay
                frameView
                    .padding(.top, 4)

                // Controls
                controlsView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .principal) {
                Text("\(Int(delivery.fps)) fps")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    exportAnnotations()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear { extractor.loadFirstFrame() }
    }

    // MARK: - Frame View

    private var frameView: some View {
        GeometryReader { geo in
            ZStack {
                // Video frame
                if let image = extractor.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { inner in
                    Color.clear.preference(key: FrameSizeKey.self, value: inner.size)
                }
            )
            .onPreferenceChange(FrameSizeKey.self) { frameSize = $0 }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
            .overlay {
                // Annotation dots
                annotationOverlay
                // Measurement line
                measurementOverlay
                // Reference calibration line
                calibrationOverlay
            }
        }
    }

    // MARK: - Annotation Overlay

    private var annotationOverlay: some View {
        GeometryReader { geo in
            ForEach(delivery.annotations.filter { $0.frameIndex == extractor.currentFrameIndex }) { ann in
                let x = ann.point.x * geo.size.width
                let y = ann.point.y * geo.size.height
                VStack(spacing: 2) {
                    Circle()
                        .fill(ann.phase.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    Text(ann.phase.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ann.phase.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.7))
                        .cornerRadius(4)
                }
                .position(x: x, y: y - 16)
            }
        }
    }

    // MARK: - Measurement Overlay

    private var measurementOverlay: some View {
        GeometryReader { geo in
            ForEach(delivery.measurements.filter { $0.frameIndex == extractor.currentFrameIndex }) { m in
                let p1 = CGPoint(x: m.point1.x * geo.size.width, y: m.point1.y * geo.size.height)
                let p2 = CGPoint(x: m.point2.x * geo.size.width, y: m.point2.y * geo.size.height)
                let dist = session.distanceFeet(from: m.point1, to: m.point2)

                Path { path in
                    path.move(to: p1)
                    path.addLine(to: p2)
                }
                .stroke(.cyan, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))

                if let dist {
                    Text(String(format: "%.1f ft", dist))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(4)
                        .background(.black.opacity(0.7))
                        .cornerRadius(4)
                        .position(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 - 14)
                }
            }
        }
    }

    // MARK: - Calibration Overlay

    private var calibrationOverlay: some View {
        GeometryReader { geo in
            if let p1 = session.referencePoint1 {
                let pos = CGPoint(x: p1.x * geo.size.width, y: p1.y * geo.size.height)
                Circle().fill(.yellow).frame(width: 12, height: 12).position(pos)
            }
            if let p1 = session.referencePoint1, let p2 = session.referencePoint2 {
                let pos1 = CGPoint(x: p1.x * geo.size.width, y: p1.y * geo.size.height)
                let pos2 = CGPoint(x: p2.x * geo.size.width, y: p2.y * geo.size.height)
                Path { path in
                    path.move(to: pos1)
                    path.addLine(to: pos2)
                }
                .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [4, 2]))

                Text(String(format: "%.0f ft", session.referenceDistanceFeet))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(3)
                    .background(.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(x: (pos1.x + pos2.x) / 2, y: (pos1.y + pos2.y) / 2 - 12)
            }
        }
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 12) {
            // Frame counter + time
            HStack {
                Text("Frame \(extractor.currentFrameIndex + 1) / \(extractor.totalFrames)")
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(extractor.currentTimeString)
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundColor(.gray)
            .padding(.horizontal)

            // Frame scrubber
            HStack(spacing: 16) {
                // Skip back 10
                Button { extractor.advance(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                }

                // Previous frame
                Button { extractor.previousFrame() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                }

                // Slider
                Slider(
                    value: Binding(
                        get: { Double(extractor.currentFrameIndex) },
                        set: { extractor.seekToFrame(Int($0)) }
                    ),
                    in: 0...Double(max(1, extractor.totalFrames - 1)),
                    step: 1
                )

                // Next frame
                Button { extractor.nextFrame() } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.bold())
                }

                // Skip forward 10
                Button { extractor.advance(by: 10) } label: {
                    Image(systemName: "goforward.10")
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal)

            // Phase markers — jump to marked phases
            if !delivery.annotations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(delivery.annotations.sorted(by: { $0.frameIndex < $1.frameIndex })) { ann in
                            Button {
                                extractor.seekToFrame(ann.frameIndex)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(ann.phase.color).frame(width: 6, height: 6)
                                    Text("\(ann.phase.rawValue) @\(ann.frameIndex)")
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ann.phase.color.opacity(0.15))
                                .cornerRadius(6)
                            }
                            .foregroundColor(ann.phase.color)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Tool bar: phase selection + measure + calibrate
            HStack(spacing: 8) {
                // Phase buttons
                ForEach(DeliveryPhase.allCases) { phase in
                    Button {
                        measureMode = false
                        calibrateMode = false
                        activePhase = activePhase == phase ? nil : phase
                    } label: {
                        Text(phase.rawValue)
                            .font(.system(size: 11, weight: activePhase == phase ? .bold : .regular))
                            .foregroundColor(activePhase == phase ? .black : phase.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(activePhase == phase ? phase.color : phase.color.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 4)

            // Measure + Calibrate
            HStack(spacing: 12) {
                Button {
                    activePhase = nil
                    measureMode = false
                    calibrateMode.toggle()
                    measurePoint1 = nil
                } label: {
                    Label("Calibrate", systemImage: "ruler")
                        .font(.caption.bold())
                        .foregroundColor(calibrateMode ? .black : .yellow)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(calibrateMode ? .yellow : .yellow.opacity(0.15))
                        .cornerRadius(8)
                }

                Button {
                    activePhase = nil
                    calibrateMode = false
                    measureMode.toggle()
                    measurePoint1 = nil
                } label: {
                    Label("Measure", systemImage: "arrow.left.and.right")
                        .font(.caption.bold())
                        .foregroundColor(measureMode ? .black : .cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(measureMode ? .cyan : .cyan.opacity(0.15))
                        .cornerRadius(8)
                }

                if session.isCalibrated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Ref set")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let normalized = CGPoint(x: location.x / size.width, y: location.y / size.height)

        if let phase = activePhase {
            // Remove existing annotation for this phase (one per phase)
            delivery.annotations.removeAll { $0.phase == phase }
            delivery.annotations.append(PhaseAnnotation(
                phase: phase,
                point: normalized,
                frameIndex: extractor.currentFrameIndex
            ))
        } else if calibrateMode {
            if session.referencePoint1 == nil || session.referencePoint2 != nil {
                // Start new calibration
                session.referencePoint1 = normalized
                session.referencePoint2 = nil
                session.isCalibrated = false
            } else {
                // Complete calibration
                session.referencePoint2 = normalized
                session.isCalibrated = true
                calibrateMode = false
            }
        } else if measureMode {
            if measurePoint1 == nil {
                measurePoint1 = normalized
            } else {
                delivery.measurements.append(DistanceMeasurement(
                    point1: measurePoint1!,
                    point2: normalized,
                    frameIndex: extractor.currentFrameIndex
                ))
                measurePoint1 = nil
            }
        }
    }

    // MARK: - Export

    private func exportAnnotations() {
        var data: [String: Any] = [
            "fps": delivery.fps,
            "totalFrames": delivery.totalFrames,
            "duration": delivery.duration,
            "referenceDistanceFeet": session.referenceDistanceFeet
        ]

        let anns = delivery.annotations.map { ann -> [String: Any] in
            [
                "phase": ann.phase.rawValue,
                "frameIndex": ann.frameIndex,
                "timeSeconds": Double(ann.frameIndex) / delivery.fps,
                "point": ["x": ann.point.x, "y": ann.point.y]
            ]
        }
        data["annotations"] = anns

        let measures = delivery.measurements.map { m -> [String: Any] in
            var dict: [String: Any] = [
                "frameIndex": m.frameIndex,
                "point1": ["x": m.point1.x, "y": m.point1.y],
                "point2": ["x": m.point2.x, "y": m.point2.y]
            ]
            if let dist = session.distanceFeet(from: m.point1, to: m.point2) {
                dict["distanceFeet"] = dist
            }
            return dict
        }
        data["measurements"] = measures

        if let json = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
           let str = String(data: json, encoding: .utf8) {
            let av = UIActivityViewController(activityItems: [str], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }
        }
    }
}

// MARK: - Preference Key

struct FrameSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
