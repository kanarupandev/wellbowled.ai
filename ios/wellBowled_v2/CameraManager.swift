import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var recordingCompletion: ((URL, Double, Double, Int) -> Void)?
    private var maxDurationTimer: Timer?

    static let maxRecordingSeconds: Double = 10.0

    @Published var isRecording = false
    @Published var achievedFPS: Double = 0
    @Published var isConfigured = false
    @Published var error: String?

    func configure() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .inputPriority

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            error = "No back camera"
            captureSession.commitConfiguration()
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            error = "Cannot access camera"
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(movieOutput) { captureSession.addOutput(movieOutput) }

        selectHighestFrameRate(device: device)
        captureSession.commitConfiguration()
        isConfigured = true
    }

    private func selectHighestFrameRate(device: AVCaptureDevice) {
        var bestFormat: AVCaptureDevice.Format?
        var bestFPS: Float64 = 0

        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= 1280 else { continue }

            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate > bestFPS {
                    bestFPS = range.maxFrameRate
                    bestFormat = format
                }
            }
        }

        guard let format = bestFormat else {
            error = "No high frame rate format"
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(bestFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            achievedFPS = bestFPS
        } catch {
            self.error = "Config failed: \(error.localizedDescription)"
        }
    }

    func startSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.stopRunning()
        }
    }

    func startRecording(completion: @escaping (URL, Double, Double, Int) -> Void) {
        guard !isRecording else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("delivery_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: url)
        recordingCompletion = completion
        movieOutput.startRecording(to: url, recordingDelegate: self)
        DispatchQueue.main.async {
            self.isRecording = true
            self.maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingSeconds, repeats: false) { [weak self] _ in
                self?.stopRecording()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        movieOutput.stopRecording()
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.isRecording = false }

        if let error {
            DispatchQueue.main.async { self.error = error.localizedDescription }
            return
        }

        Task {
            let asset = AVAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let dur = (try? await asset.load(.duration))?.seconds ?? 0
            let fr = Double((try? await track.load(.nominalFrameRate)) ?? 120)
            let frames = Int(dur * fr)

            await MainActor.run {
                self.recordingCompletion?(url, fr, dur, frames)
            }
        }
    }
}
