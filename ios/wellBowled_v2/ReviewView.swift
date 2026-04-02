import SwiftUI

struct ReviewView: View {
    let delivery: Delivery
    let onSave: (Int, Int) -> Void   // (releaseFrame, arrivalFrame)
    let onDismiss: () -> Void

    @StateObject private var extractor: FrameExtractor
    @State private var releaseFrame: Int?
    @State private var arrivalFrame: Int?

    init(delivery: Delivery, onSave: @escaping (Int, Int) -> Void, onDismiss: @escaping () -> Void) {
        self.delivery = delivery
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._extractor = StateObject(wrappedValue: FrameExtractor(
            url: delivery.videoURL, fps: delivery.fps,
            duration: delivery.duration, totalFrames: delivery.totalFrames
        ))
        self._releaseFrame = State(initialValue: delivery.releaseFrame)
        self._arrivalFrame = State(initialValue: delivery.arrivalFrame)
    }

    private var step: Step {
        if releaseFrame != nil && arrivalFrame != nil { return .done }
        if releaseFrame != nil { return .pickArrival }
        return .scrubbing
    }

    private enum Step { case scrubbing, pickArrival, done }

    // Speed computed from local state
    private var speedKMH: Double? {
        guard let r = releaseFrame, let a = arrivalFrame, a > r else { return nil }
        let seconds = Double(a - r) / delivery.fps
        return (Delivery.pitchMeters / seconds) * 3.6
    }

    private var speedMPH: Double? {
        guard let kmh = speedKMH else { return nil }
        return kmh / 1.609
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
            // Frame info
            HStack {
                Text("Frame \(extractor.currentFrameIndex + 1) / \(extractor.totalFrames)")
                Spacer()
                Text(extractor.currentTimeString)
                Spacer()
                Text("\(Int(delivery.fps)) fps")
                    .foregroundColor(.secondary)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.gray)
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
                            onSave(r, a)
                        }
                    }
                }

            case .done:
                speedResultView
            }

            // Done button
            Button {
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

    // MARK: - Speed Result

    private var speedResultView: some View {
        VStack(spacing: 8) {
            if let kmh = speedKMH, let cat = category {
                HStack(spacing: 20) {
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
                        Text("\(frameDiff ?? 0)f @ \(Int(delivery.fps))fps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal)
                .background(cat.color.opacity(0.1))
                .cornerRadius(12)

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
}
