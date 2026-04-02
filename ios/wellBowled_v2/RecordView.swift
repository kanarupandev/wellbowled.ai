import SwiftUI
import AVFoundation

struct RecordView: View {
    let onCapture: (Delivery) -> Void
    let onDismiss: () -> Void

    @StateObject private var camera = CameraManager()
    @State private var recordingSeconds: Double = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.captureSession)
                .ignoresSafeArea()

            VStack {
                // Top bar
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

                    Button { onDismiss() } label: {
                        Text("Close")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

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
                .padding(.bottom, 40)
            }

            if let error = camera.error {
                Text(error)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .onAppear {
            camera.configure()
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
    }

    private func startRecording() {
        recordingSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingSeconds += 0.1
        }
        camera.startRecording { url, fps, duration, frames in
            let delivery = Delivery(videoURL: url, fps: fps, duration: duration, totalFrames: frames)
            onCapture(delivery)
            onDismiss()
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        camera.stopRecording()
    }
}
