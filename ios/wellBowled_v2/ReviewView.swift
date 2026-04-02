import SwiftUI

struct ReviewView: View {
    @Binding var delivery: Delivery
    @StateObject private var extractor: FrameExtractor
    @Environment(\.dismiss) var dismiss

    @State private var step: Step = .scrubbing

    enum Step {
        case scrubbing      // free scrub, pick release
        case pickArrival    // release set, pick arrival
        case done           // both set, show speed
    }

    init(delivery: Binding<Delivery>) {
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
                // Frame image
                frameView
                // Controls
                controlsView
            }
        }
        .onAppear {
            extractor.loadFirstFrame()
            // Resume state if already marked
            if delivery.releaseFrame != nil && delivery.arrivalFrame != nil {
                step = .done
            } else if delivery.releaseFrame != nil {
                step = .pickArrival
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
        .overlay(alignment: .topLeading) {
            frameMarkerOverlay
        }
    }

    private var frameMarkerOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = delivery.releaseFrame, extractor.currentFrameIndex == r {
                markerBadge("RELEASE", color: .orange)
            }
            if let a = delivery.arrivalFrame, extractor.currentFrameIndex == a {
                markerBadge("ARRIVAL", color: .green)
            }
        }
        .padding(8)
    }

    private func markerBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 10) {
            // Frame info
            HStack {
                Text("Frame \(extractor.currentFrameIndex + 1) / \(extractor.totalFrames)")
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(extractor.currentTimeString)
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text("\(Int(delivery.fps)) fps")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
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

            // Action area — depends on step
            switch step {
            case .scrubbing:
                actionButton("Mark Release Frame", color: .orange) {
                    delivery.releaseFrame = extractor.currentFrameIndex
                    step = .pickArrival
                }

            case .pickArrival:
                VStack(spacing: 8) {
                    HStack {
                        markerBadge("Release @ \(delivery.releaseFrame! + 1)", color: .orange)
                        Spacer()
                        Button("Reset") {
                            delivery.releaseFrame = nil
                            delivery.arrivalFrame = nil
                            step = .scrubbing
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)

                    actionButton("Mark Arrival Frame", color: .green) {
                        delivery.arrivalFrame = extractor.currentFrameIndex
                        step = .done
                    }
                }

            case .done:
                speedResultView
            }

            // Done button
            Button {
                dismiss()
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
            if let kmh = delivery.speedKMH, let cat = delivery.category {
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
                        Text(String(format: "%.1f", delivery.speedMPH ?? 0))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        Text("mph")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text(cat.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(cat.color)
                        Text("\(delivery.frameDiff ?? 0)f @ \(Int(delivery.fps))fps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal)
                .background(cat.color.opacity(0.1))
                .cornerRadius(12)

                // Jump to marked frames
                HStack(spacing: 12) {
                    Button {
                        if let r = delivery.releaseFrame { extractor.seekToFrame(r) }
                    } label: {
                        markerBadge("Release @ \(delivery.releaseFrame! + 1)", color: .orange)
                    }

                    Button {
                        if let a = delivery.arrivalFrame { extractor.seekToFrame(a) }
                    } label: {
                        markerBadge("Arrival @ \(delivery.arrivalFrame! + 1)", color: .green)
                    }

                    Spacer()

                    Button("Redo") {
                        delivery.releaseFrame = nil
                        delivery.arrivalFrame = nil
                        step = .scrubbing
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Action Button

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
