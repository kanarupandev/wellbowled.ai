import SwiftUI
import AVFoundation

struct CaptureView: View {
    @StateObject private var camera = CameraManager()
    @State private var deliveries: [Delivery] = []
    @State private var recordingSeconds: Double = 0
    @State private var timer: Timer?
    @State private var reviewDelivery: Delivery?

    var body: some View {
        ZStack {
            // Camera preview — always behind everything
            CameraPreviewView(session: camera.captureSession)
                .ignoresSafeArea()

            VStack {
                // Top: FPS + clip count
                topBar
                Spacer()
                // Bottom: record button + stats
                bottomBar
            }

            if let error = camera.error {
                errorBanner(error)
            }
        }
        .onAppear {
            camera.configure()
            camera.startSession()
        }
        .fullScreenCover(item: $reviewDelivery) { delivery in
            ReviewView(delivery: binding(for: delivery))
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Label("\(Int(camera.achievedFPS)) fps", systemImage: "speedometer")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

            Spacer()

            if camera.isRecording {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(String(format: "%.1f / %.0fs", recordingSeconds, CameraManager.maxRecordingSeconds))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }

            Spacer()

            if !deliveries.isEmpty {
                Text("\(deliveries.count) clip\(deliveries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Speed stats from measured deliveries
            if let best = bestSpeed {
                HStack(spacing: 20) {
                    statLabel("Top", value: String(format: "%.1f", best), unit: "km/h")
                    if let avg = avgSpeed {
                        statLabel("Avg", value: String(format: "%.1f", avg), unit: "km/h")
                    }
                    statLabel("Balls", value: "\(deliveries.count)", unit: "")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }

            HStack(spacing: 40) {
                // Review last clip
                if let last = deliveries.last {
                    Button { reviewDelivery = last } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "play.fill")
                                .font(.title3)
                            if let kmh = last.speedKMH {
                                Text(String(format: "%.0f", kmh))
                                    .font(.system(size: 10, design: .monospaced))
                            } else {
                                Text("Review")
                                    .font(.system(size: 10))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.2))
                        .cornerRadius(10)
                    }
                } else {
                    Color.clear.frame(width: 50, height: 50)
                }

                // Record button
                Button {
                    camera.isRecording ? stopRecording() : startRecording()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 72, height: 72)

                        if camera.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }

                Color.clear.frame(width: 50, height: 50)
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Helpers

    private func statLabel(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            HStack(spacing: 2) {
                Text(value).font(.system(size: 18, weight: .bold, design: .monospaced))
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }

    private var bestSpeed: Double? { deliveries.compactMap(\.speedKMH).max() }
    private var avgSpeed: Double? {
        let speeds = deliveries.compactMap(\.speedKMH)
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    private func startRecording() {
        recordingSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingSeconds += 0.1
        }
        camera.startRecording { url, fps, duration, frames in
            let delivery = Delivery(videoURL: url, fps: fps, duration: duration, totalFrames: frames)
            deliveries.append(delivery)
            reviewDelivery = delivery
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        camera.stopRecording()
    }

    private func binding(for delivery: Delivery) -> Binding<Delivery> {
        guard let i = deliveries.firstIndex(where: { $0.id == delivery.id }) else {
            return .constant(delivery)
        }
        return $deliveries[i]
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .foregroundColor(.white)
            .padding()
            .background(Color.red.opacity(0.8))
            .cornerRadius(8)
    }
}
