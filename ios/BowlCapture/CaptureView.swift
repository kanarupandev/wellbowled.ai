import SwiftUI
import AVFoundation

struct CaptureView: View {
    @ObservedObject var session: BowlSession
    @StateObject private var camera = CameraManager()
    @State private var selectedDelivery: Delivery?
    @State private var recordingSeconds: Double = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: camera.captureSession)
                .ignoresSafeArea()

            VStack {
                // Top bar: FPS + delivery count
                HStack {
                    Label("\(Int(camera.achievedFPS)) fps", systemImage: "speedometer")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)

                    Spacer()

                    if camera.isRecording {
                        Text(String(format: "%.1fs", recordingSeconds))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }

                    Spacer()

                    Text("\(session.deliveries.count) clips")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                // Bottom: record button + review last
                HStack(spacing: 40) {
                    // Review last delivery
                    if let last = session.deliveries.last {
                        Button {
                            selectedDelivery = last
                        } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.3))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.white)
                                )
                        }
                    } else {
                        Color.clear.frame(width: 50, height: 50)
                    }

                    // Record button
                    Button {
                        if camera.isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
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

                    // Delivery list
                    NavigationLink {
                        DeliveryListView(session: session, selectedDelivery: $selectedDelivery)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                            Text("All")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                    }
                }
                .padding(.bottom, 30)
            }

            // Error overlay
            if let error = camera.error {
                Text(error)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            camera.configure()
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
        .fullScreenCover(item: $selectedDelivery) { delivery in
            NavigationStack {
                ReviewView(session: session, delivery: binding(for: delivery))
            }
        }
    }

    private func startRecording() {
        recordingSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingSeconds += 0.1
        }
        camera.startRecording { url, fps, duration, frames in
            let delivery = Delivery(videoURL: url, fps: fps, duration: duration, totalFrames: frames)
            session.deliveries.append(delivery)
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        camera.stopRecording()
    }

    private func binding(for delivery: Delivery) -> Binding<Delivery> {
        guard let index = session.deliveries.firstIndex(where: { $0.id == delivery.id }) else {
            // Fallback — shouldn't happen
            return .constant(delivery)
        }
        return $session.deliveries[index]
    }
}

// MARK: - Delivery List

struct DeliveryListView: View {
    @ObservedObject var session: BowlSession
    @Binding var selectedDelivery: Delivery?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(session.deliveries.reversed()) { delivery in
                Button {
                    selectedDelivery = delivery
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1fs at %.0f fps", delivery.duration, delivery.fps))
                                .font(.system(.body, design: .monospaced))
                            Text("\(delivery.totalFrames) frames")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Show marked phases
                        HStack(spacing: 4) {
                            ForEach(delivery.annotations) { ann in
                                Circle()
                                    .fill(ann.phase.color)
                                    .frame(width: 8, height: 8)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Deliveries")
        .navigationBarTitleDisplayMode(.inline)
    }
}
